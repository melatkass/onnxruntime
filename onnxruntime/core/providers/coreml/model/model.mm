// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#include "core/providers/coreml/model/model.h"

#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <cstdint>
#include <optional>
#include <unordered_map>
#include <vector>

#include "core/common/common.h"
#include <gsl/gsl>
#include "core/common/inlined_containers.h"
#include "core/common/logging/logging.h"
#include "core/common/narrow.h"
#include "core/common/span_utils.h"
#include "core/graph/onnx_protobuf.h"
#include "core/platform/env.h"
#include "core/providers/coreml/builders/helper.h"
#include "core/providers/coreml/coreml_provider_factory.h"
#include "core/providers/coreml/model/host_utils.h"
#include "core/providers/coreml/model/objc_str_utils.h"
#include "core/providers/coreml/shape_utils.h"

// force the linker to create a dependency on the CoreML framework so that in MAUI usage we don't need
// to manually do this
asm(".linker_option \"-framework\", \"CoreML\"");

using namespace onnxruntime;
using namespace onnxruntime::coreml;

namespace {
/**
 * Computes the static output shape used to allocate the output tensor.
 * `inferred_shape` is the inferred shape known at model compile time. It may contain dynamic dimensions (-1).
 * `coreml_static_shape` is the static output shape of the CoreML MLMultiArray output. It must NOT contain dynamic
 * dimensions.
 * Returns a static output shape which is `inferred_shape` with each of its dynamic dimensions replaced by the
 * corresponding static dimension from `coreml_static_shape`.
 */
InlinedVector<int64_t> GetStaticOutputShape(gsl::span<const int64_t> inferred_shape,
                                            gsl::span<const int64_t> coreml_static_shape,
                                            const logging::Logger& logger) {
  ORT_ENFORCE(IsStaticShape(coreml_static_shape),
              "CoreML output shape (", Shape2String(coreml_static_shape), ") is not static.");

  // return early if the shapes match
  if (std::equal(inferred_shape.begin(), inferred_shape.end(),
                 coreml_static_shape.begin(), coreml_static_shape.end())) {
    return InlinedVector<int64_t>(inferred_shape.begin(), inferred_shape.end());
  }

  if (inferred_shape.empty() && SpanEq(coreml_static_shape, AsSpan<int64_t>({1}))) {
    // Special case - inferred output shape is [] (scalar) and CoreML output shape is [1].
    // CoreML doesn't handle scalar multiarrays so we convert scalar inputs to shape [1] and do the reverse for scalar
    // outputs.
    return InlinedVector<int64_t>{};
  }

  ORT_ENFORCE(inferred_shape.size() == coreml_static_shape.size(),
              "CoreML static output shape (", Shape2String(coreml_static_shape),
              ") and inferred shape (", Shape2String(inferred_shape), ") have different ranks.");

  InlinedVector<int64_t> static_shape{};
  static_shape.reserve(inferred_shape.size());
  std::transform(inferred_shape.begin(), inferred_shape.end(),
                 coreml_static_shape.begin(),
                 std::back_inserter(static_shape),
                 [&](int64_t inferred_dim, int64_t coreml_static_dim) {
                   ORT_ENFORCE(inferred_dim == -1 || inferred_dim == coreml_static_dim,
                               "CoreML static output shape (", Shape2String(coreml_static_shape),
                               ") and inferred shape (", Shape2String(inferred_shape),
                               ") have an inconsistent static dimensions (", coreml_static_dim, " vs. ",
                               inferred_dim, ").");

                   return inferred_dim != -1 ? inferred_dim : coreml_static_dim;
                 });

  return static_shape;
}

Status CreateInputFeatureProvider(const std::unordered_map<std::string, OnnxTensorData>& inputs,
                                  const logging::Logger& logger,
                                  id<MLFeatureProvider> __autoreleasing* _Nonnull feature_provider_out,
                                  InlinedVector<std::unique_ptr<int32_t[]>>& conversion_buffers_out) {
  NSError* error = nil;
  InlinedVector<std::unique_ptr<int32_t[]>> conversion_buffers{};
  NSMutableDictionary* feature_dictionary = [NSMutableDictionary dictionaryWithCapacity:inputs.size()];

  // create a MLMultiArray feature for each input
  for (const auto& [name, onnx_tensor_data] : inputs) {
    const auto& shape = onnx_tensor_data.tensor_info.shape;

    NSMutableArray* shape_array = [NSMutableArray arrayWithCapacity:shape.size()];
    for (const auto dim : shape) {
      [shape_array addObject:[NSNumber numberWithLongLong:dim]];
    }

    NSMutableArray* strides_array = [NSMutableArray arrayWithCapacity:shape.size()];
    {
      int64_t stride = 1;
      for (size_t idx = 0; idx < shape.size(); ++idx) {
        const size_t idx_from_end = shape.size() - 1 - idx;
        [strides_array insertObject:[NSNumber numberWithLongLong:stride]
                            atIndex:0];

        stride *= shape[idx_from_end];
      }
    }

    MLMultiArrayDataType data_type;
    void* data_pointer = onnx_tensor_data.buffer;

    switch (onnx_tensor_data.tensor_info.data_type) {
      case ONNX_NAMESPACE::TensorProto_DataType_FLOAT: {
        data_type = MLMultiArrayDataTypeFloat32;
        break;
      }
      case ONNX_NAMESPACE::TensorProto_DataType_INT32: {
        data_type = MLMultiArrayDataTypeInt32;
        break;
      }
      case ONNX_NAMESPACE::TensorProto_DataType_INT64: {
        // CoreML doesn't support int64 input so convert to int32 input.
        data_type = MLMultiArrayDataTypeInt32;

        // Convert the data and store it in a buffer. Add the buffer to `conversion_buffers`.
        const auto num_elements = narrow<size_t>(ShapeSize(shape));
        const auto input_span = gsl::span{static_cast<const int64_t*>(onnx_tensor_data.buffer), num_elements};
        auto conversion_buffer = std::make_unique<int32_t[]>(num_elements);
        const auto conversion_span = gsl::span{conversion_buffer.get(), num_elements};
        std::transform(input_span.begin(), input_span.end(), conversion_span.begin(),
                       [](int64_t v) { return narrow<int32_t>(v); });

        conversion_buffers.emplace_back(std::move(conversion_buffer));
        data_pointer = conversion_buffers.back().get();

        break;
      }
      default: {
        return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "Output data type is not supported, actual type: ",
                               onnx_tensor_data.tensor_info.data_type);
      }
    }

    MLMultiArray* multi_array = [[MLMultiArray alloc] initWithDataPointer:data_pointer
                                                                    shape:shape_array
                                                                 dataType:data_type
                                                                  strides:strides_array
                                                              deallocator:^(void* /* bytes */) {
                                                              }
                                                                    error:&error];
    ORT_RETURN_IF(error != nil || multi_array == nil,
                  "Failed to create MLMultiArray for feature: ", name,
                  (error != nil) ? MakeString(", error: ", [[error localizedDescription] UTF8String]) : "");

    MLFeatureValue* feature_value = [MLFeatureValue featureValueWithMultiArray:multi_array];
    NSString* feature_name = util::Utf8StringToNSString(name.c_str());
    feature_dictionary[feature_name] = feature_value;
  }

  auto* feature_provider = [[MLDictionaryFeatureProvider alloc] initWithDictionary:feature_dictionary
                                                                             error:&error];
  ORT_RETURN_IF(error != nil || feature_provider == nil,
                "Failed to create MLDictionaryFeatureProvider",
                (error != nil) ? MakeString(", error: ", [[error localizedDescription] UTF8String]) : "");

  *feature_provider_out = feature_provider;
  conversion_buffers_out = std::move(conversion_buffers);
  return Status::OK();
}

Status CopyMLMultiArrayBuffer(const void* mlmultiarray_buffer, void* tensor_buffer,
                              const MLMultiArray* array,
                              const int64_t num_blocks, const int64_t block_size, const int64_t stride,
                              const OnnxTensorInfo* tensor_info) {
  if (mlmultiarray_buffer == nullptr) {
    return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "mlmultiarray_buffer has no data");
  }

  // total including non-contiguous space

  int64_t array_total_elements = [array.strides[0] longLongValue] * [array.shape[0] longLongValue];
  const int64_t num_elements = array.count;

  ORT_RETURN_IF(array_total_elements != num_blocks * stride ||
                    num_elements != num_blocks * block_size,
                "MLMultiArray size does not match the copy info");

  const auto onnx_data_type = tensor_info->data_type;
  switch (onnx_data_type) {
    case ONNX_NAMESPACE::TensorProto_DataType_FLOAT: {
      const auto* src_buffer = static_cast<const float*>(mlmultiarray_buffer);
      auto* dst_buffer = static_cast<float*>(tensor_buffer);
      const auto block_byte_size = block_size * sizeof(float);

      for (int64_t idx = 0; idx < num_blocks; ++idx) {
        memcpy(dst_buffer, src_buffer, block_byte_size);
        src_buffer += stride;
        dst_buffer += block_size;
      }
      break;
    }
    case ONNX_NAMESPACE::TensorProto_DataType_INT32: {
      const auto* src_buffer = static_cast<const int32_t*>(mlmultiarray_buffer);
      auto* dst_buffer = static_cast<int32_t*>(tensor_buffer);
      const auto block_byte_size = block_size * sizeof(int32_t);

      for (int64_t idx = 0; idx < num_blocks; ++idx) {
        memcpy(dst_buffer, src_buffer, block_byte_size);
        src_buffer += stride;
        dst_buffer += block_size;
      }

      break;
    }
    // For this case, since Coreml Spec only uses int32 for model output while onnx provides
    // int64 for model output data type. We are doing a type casting (int32 -> int64) here
    // when copying the model to ORT
    case ONNX_NAMESPACE::TensorProto_DataType_INT64: {
      ORT_RETURN_IF(array.dataType != MLMultiArrayDataTypeInt32,
                    "CoreML output data type is not MLMultiArrayDataTypeInt32");

      const int32_t* src_buffer = static_cast<const int32_t*>(mlmultiarray_buffer);
      int64_t* dst_buffer = static_cast<int64_t*>(tensor_buffer);

      for (int64_t idx = 0; idx < num_blocks; ++idx) {
        auto input_span = gsl::span{src_buffer, static_cast<size_t>(block_size)};
        auto output_span = gsl::span{dst_buffer, static_cast<size_t>(block_size)};
        std::transform(input_span.begin(), input_span.end(), output_span.begin(),
                       [](int32_t v) { return static_cast<int64_t>(v); });

        src_buffer += stride;
        dst_buffer += block_size;
      }
      break;
    }
    default:
      return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL,
                             "Output data type is not supported, actual type: ", onnx_data_type);
  }
  return Status::OK();
}
}  // namespace

NS_ASSUME_NONNULL_BEGIN

// Execution for a CoreML model, it performs
// 1. Compile the model by given path for execution
// 2. Predict using given OnnxTensorFeatureProvider input and copy the output data back ORT
// 3. The compiled model will be removed in dealloc or removed using cleanup function
@interface CoreMLExecution : NSObject {
  NSString* coreml_model_path_;
  NSString* compiled_model_path_;
  const logging::Logger* logger_;
  uint32_t coreml_flags_;
}

- (instancetype)initWithPath:(const std::string&)path
                      logger:(const logging::Logger&)logger
                coreml_flags:(uint32_t)coreml_flags;
- (void)cleanup;
- (void)dealloc;
- (Status)loadModel API_AVAILABLE_COREML3;
- (Status)predict:(const std::unordered_map<std::string, OnnxTensorData>&)inputs
                  outputs:(const std::unordered_map<std::string, OnnxTensorInfo>&)outputs
    getOutputTensorDataFn:(const GetOutputTensorMutableRawDataFn&)get_output_tensor_mutable_raw_data_fn
    API_AVAILABLE_COREML3;

@property(nullable) MLModel* model API_AVAILABLE_COREML3;

@end

@implementation CoreMLExecution

- (instancetype)initWithPath:(const std::string&)path
                      logger:(const logging::Logger&)logger
                coreml_flags:(uint32_t)coreml_flags {
  if (self = [super init]) {
    coreml_model_path_ = util::Utf8StringToNSString(path.c_str());
    logger_ = &logger;
    coreml_flags_ = coreml_flags;
  }
  return self;
}

- (void)cleanup {
  NSError* error = nil;
  if (compiled_model_path_ != nil) {
    [[NSFileManager defaultManager] removeItemAtPath:compiled_model_path_ error:&error];
    if (error != nil) {
      LOGS(*logger_, ERROR) << "Failed cleaning up the compiled model: " << [compiled_model_path_ UTF8String]
                            << ", error message: " << [[error localizedDescription] UTF8String];
    }
    compiled_model_path_ = nil;
  }

#if !defined(NDEBUG)
  std::string path_override = Env::Default().GetEnvironmentVar(util::kOverrideModelOutputDirectoryEnvVar);
  if (!path_override.empty()) {
    // don't cleanup
    coreml_model_path_ = nil;
  }
#endif

  if (coreml_model_path_ != nil) {
    error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:coreml_model_path_ error:&error];
    if (error != nil) {
      LOGS(*logger_, ERROR) << "Failed cleaning up the coreml model: " << [coreml_model_path_ UTF8String]
                            << ", error message: " << [[error localizedDescription] UTF8String];
    }
    coreml_model_path_ = nil;
  }
}

- (void)dealloc {
  [self cleanup];
}

- (Status)loadModel {
  NSURL* modelUrl = [NSURL URLWithString:coreml_model_path_];
  if (modelUrl == nil) {
    return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "Failed to create model URL from path");
  }

  // TODO: Update this to version with callback handler as the API used here is deprecated.
  // https://developer.apple.com/documentation/coreml/mlmodel/3929553-compilemodelaturl
  // As we call loadModel during EP Compile there shouldn't be an issue letting the actual compile run in the
  // background. We will have to check for completion in `predict` and block until it is done.
  NSError* error = nil;
  NSURL* compileUrl = [MLModel compileModelAtURL:modelUrl error:&error];

  if (error != nil) {
    return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "Error compiling model: ",
                           [[error localizedDescription] UTF8String]);
  }

  compiled_model_path_ = [compileUrl path];

  MLModelConfiguration* config = [MLModelConfiguration alloc];
  config.computeUnits = (coreml_flags_ & COREML_FLAG_USE_CPU_ONLY)
                            ? MLComputeUnitsCPUOnly
                            : MLComputeUnitsAll;
  _model = [MLModel modelWithContentsOfURL:compileUrl configuration:config error:&error];

  if (error != nil || _model == nil) {
    return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "Failed to create MLModel",
                           (error != nil) ? MakeString(", error: ", [[error localizedDescription] UTF8String]) : "");
  }

  return Status::OK();
}

- (Status)predict:(const std::unordered_map<std::string, OnnxTensorData>&)inputs
                  outputs:(const std::unordered_map<std::string, OnnxTensorInfo>&)outputs
    getOutputTensorDataFn:(const GetOutputTensorMutableRawDataFn&)get_output_tensor_mutable_raw_data_fn {
  Status status = Status::OK();
  ORT_TRY {
    if (_model == nil) {
      return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "Model is not loaded");
    }

    id<MLFeatureProvider> input_features;
    InlinedVector<std::unique_ptr<int32_t[]>> conversion_buffers;
    ORT_RETURN_IF_ERROR(CreateInputFeatureProvider(inputs, *logger_, &input_features, conversion_buffers));

    MLPredictionOptions* options = [[MLPredictionOptions alloc] init];
    NSError* error = nil;
    id<MLFeatureProvider> output_features = [_model predictionFromFeatures:input_features
                                                                   options:options
                                                                     error:&error];

    if (error != nil) {
      return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "Error executing model: ",
                             [[error localizedDescription] UTF8String]);
    }

    for (const auto& [output_name, output_tensor_info] : outputs) {
      MLFeatureValue* output_value =
          [output_features featureValueForName:util::Utf8StringToNSString(output_name.c_str())];

      if (output_value == nil) {
        return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "output_features has no value for ", output_name);
      }

      MLMultiArray* data = [output_value multiArrayValue];

      const auto coreml_static_output_shape = [data]() {
        InlinedVector<int64_t> result;
        result.reserve(data.shape.count);
        for (NSNumber* dim in data.shape) {
          const auto dim_value = dim.longLongValue;
          result.push_back(dim_value);
        }
        return result;
      }();

      const auto static_output_shape = GetStaticOutputShape(output_tensor_info.shape, coreml_static_output_shape,
                                                            *logger_);

      void* output_buffer = get_output_tensor_mutable_raw_data_fn(output_name, output_tensor_info.data_type,
                                                                  static_output_shape);

      if (const size_t num_elements = data.count; num_elements > 0) {
        if (const auto shape_size = ShapeSize(static_output_shape);
            shape_size < 0 || num_elements != static_cast<size_t>(shape_size)) {
          return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL,
                                 "CoreML MLMultiArray count (", num_elements, ") and shape size (", shape_size,
                                 ") do not match");
        }

        // support a non-contiguous array, provided only one dimension is not contiguous
        int64_t num_blocks = 0;
        int64_t block_size = 0;
        int64_t stride = 0;

        ORT_RETURN_IF_ERROR(GetMLMultiArrayCopyInfo(data, num_blocks, block_size, stride));

        __block Status copy_status;
        const auto* tensor_info = &output_tensor_info;
        // `getBytesWithHandler` replaces deprecated `.dataPointer` on new versions
        if (@available(macOS 12.3, iOS 15.4, *)) {
          [data getBytesWithHandler:^(const void* bytes, NSInteger size) {
            copy_status = CopyMLMultiArrayBuffer(bytes, output_buffer, data,
                                                 num_blocks, block_size, stride, tensor_info);
          }];
        } else {
          copy_status = CopyMLMultiArrayBuffer(data.dataPointer, output_buffer, data,
                                               num_blocks, block_size, stride, tensor_info);
        }

        ORT_RETURN_IF_ERROR(copy_status);
      }
    }
  }
  ORT_CATCH(const std::exception& e) {
    ORT_HANDLE_EXCEPTION([&]() {
      status = ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "Exception: ", e.what());
    });
  }

  return status;
}

@end

NS_ASSUME_NONNULL_END

namespace onnxruntime {
namespace coreml {

Status GetMLMultiArrayCopyInfo(const MLMultiArray* _Nonnull array,
                               int64_t& num_blocks, int64_t& block_size, int64_t& stride) {
  const auto* shape = array.shape;
  const auto rank = shape.count;

  int64_t array_total_elements = [array.strides[0] longLongValue] * [shape[0] longLongValue];

  int64_t data_elems = 1;   // actual values
  int64_t total_elems = 1;  // elems including empty slots if non-contiguous
  for (unsigned long i = 1; i <= rank; i++) {
    int64_t this_stride = [array.strides[rank - i] longLongValue];
    if (this_stride != total_elems) {
      // non-contiguous
      if (block_size != 0) {
        return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL,
                               "Multiple non-contiguous dimensions in MLMultiArray are not supported.");
      }

      block_size = data_elems;
      stride = this_stride;
    }

    const auto elems_this_dim = [shape[rank - i] longLongValue];
    data_elems *= elems_this_dim;
    total_elems = elems_this_dim * this_stride;
  }

  if (block_size == 0) {
    // all data is contiguous
    block_size = data_elems;
    stride = array_total_elements;
    assert(block_size == stride);
  }

  num_blocks = data_elems / block_size;

  ORT_ENFORCE(array_total_elements == total_elems, "Logic error calculating copy info");
  ORT_ENFORCE(stride >= block_size, "Logic error calculating copy info");
  ORT_ENFORCE(stride * num_blocks == total_elems, "Logic error calculating copy info");

  return Status::OK();
}

// Internal Execution class
// This class will bridge Model (c++) with CoreMLExecution (objective c++)
class Execution {
 public:
  Execution(const std::string& path, const logging::Logger& logger, uint32_t coreml_flags);
  ~Execution(){};

  Status LoadModel();
  Status Predict(const std::unordered_map<std::string, OnnxTensorData>& inputs,
                 const std::unordered_map<std::string, OnnxTensorInfo>& outputs,
                 const GetOutputTensorMutableRawDataFn& get_output_tensor_mutable_raw_data_fn);

 private:
  bool model_loaded{false};
  CoreMLExecution* execution_;
};

Execution::Execution(const std::string& path, const logging::Logger& logger, uint32_t coreml_flags) {
  @autoreleasepool {
    execution_ = [[CoreMLExecution alloc] initWithPath:path
                                                logger:logger
                                          coreml_flags:coreml_flags];
  }
}

Status Execution::LoadModel() {
  if (model_loaded) {
    return Status::OK();
  }

  if (HAS_COREML3_OR_LATER) {
    Status status{};
    @autoreleasepool {
      status = [execution_ loadModel];
    }
    model_loaded = status.IsOK();
    return status;
  }

  return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "Execution::LoadModel requires macos 10.15+ or ios 13+");
}

Status Execution::Predict(const std::unordered_map<std::string, OnnxTensorData>& inputs,
                          const std::unordered_map<std::string, OnnxTensorInfo>& outputs,
                          const GetOutputTensorMutableRawDataFn& get_output_tensor_mutable_raw_data_fn) {
  ORT_RETURN_IF_NOT(model_loaded, "Execution::Predict requires Execution::LoadModel");

  if (HAS_COREML3_OR_LATER) {
    @autoreleasepool {
      return [execution_ predict:inputs
                         outputs:outputs
           getOutputTensorDataFn:get_output_tensor_mutable_raw_data_fn];
    }
  }

  return ORT_MAKE_STATUS(ONNXRUNTIME, FAIL, "Execution::Predict requires macos 10.15+ or ios 13+");
}

Model::Model(const std::string& path,
             std::vector<std::string>&& model_input_names,
             std::vector<std::string>&& model_output_names,
             std::unordered_map<std::string, OnnxTensorInfo>&& input_output_info,
             std::unordered_set<std::string>&& scalar_outputs,
             std::unordered_set<std::string>&& int64_outputs,
             const logging::Logger& logger,
             uint32_t coreml_flags)
    : execution_(std::make_unique<Execution>(path, logger, coreml_flags)),
      model_input_names_(std::move(model_input_names)),
      model_output_names_(std::move(model_output_names)),
      input_output_info_(std::move(input_output_info)),
      scalar_outputs_(std::move(scalar_outputs)),
      int64_outputs_(std::move(int64_outputs)) {
}

Model::~Model() {}

Status Model::LoadModel() {
  return execution_->LoadModel();
}

Status Model::Predict(const std::unordered_map<std::string, OnnxTensorData>& inputs,
                      const std::unordered_map<std::string, OnnxTensorInfo>& outputs,
                      const GetOutputTensorMutableRawDataFn& get_output_tensor_mutable_raw_data_fn) {
  return execution_->Predict(inputs, outputs, get_output_tensor_mutable_raw_data_fn);
}
}  // namespace coreml
}  // namespace onnxruntime
