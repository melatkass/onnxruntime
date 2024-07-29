<div class="h-14 w-170 bg-gradient-to-r from-bg-base-200 to-cyan-500"></div>
<script>

	import { blackMetal } from "svelte-highlight/styles";

</script>
<div class="container">
   
</div>

<head>

    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">


    
</head>

<style>

.bordered {
            border: 10px; /* Fallback for browsers that do not support border-image */
            border-image: url('R.png') 30 round;
            padding: 30px; /* Specify the image and how it should be applied */

        }
img {
  border-radius: 10px;
  margin: auto;
  padding: 0px;
  
}

.spacer{
    margin: 25px;
    }




.parent {
  position: relative;
  top: 0;
  left: 0;
}
.image1 {
  position: relative;
  top: 0;
  left: 0;
  border: 3px rgb(3, 215, 243) solid;
}
.image2 {
  position: absolute;
  bottom: 450px;
  right: 100px;
  width: 10%;
  height: 20;
  padding: 10;
}

.image1:hover {
  box-shadow: 0 0 3px 1px rgba(1, 181, 241, 0.5);
}

@media (max-width: 600px) {
    img {
        width: 80%; 

    }
}

@media (min-width: 601px) and (max-width: 1200px) {
    img {
        width: 100%; /* Half width on medium screens */
    }
}


@media (min-width: 1201px) {
    img {
        width: 100%; /* Quarter width on large screens */
    }
}

</style>
  


<div class="container">
<div class="parent">
    <img class="image1" src="https://www.blognone.com/sites/default/files/externals/90c931f154e3055001e5ea65fa5ce222.png"/>
    <img class="image2" src="https://static.vecteezy.com/system/resources/previews/019/017/455/non_2x/microsoft-transparent-logo-free-png.png"/>

  <div class="h-14 w-170 bg-gradient-to-r from-bg-base-200 to-cyan-500"></div>
</div>
<!-- Card border, set the border color and structure. the title will be in the border. -->
<div>
  <div class="card bg-base-300 text-primary-content w-100 border-4 border-cyan-400 h-128 w-150 p-0">
      <h2 class="card-title justify-start text-4xl bg-base-300 rounded-box">Why ONNX Runtime?</h2>
    <div class="flex w-full flex-col">
        <div class="h-14 w-170 bg-gradient-to-r from-bg-base-200 to-cyan-500"></div>
        <div class="card bg-base-300 rounded-box grid h-200 w-100 place-items-center shadow-sm hover:bg-primary text-2xl p-5">Supports the Open Neural Network Exchange, models trained from different frameworks can be converted to the ONNX format and run on all supported platforms.</div>
        <div class="h-14 w-170 bg-gradient-to-r from-bg-base-200 to-cyan-500"></div>
        <div class="card bg-base-300 rounded-box grid h-200 w-100 place-items-center shadow-sm hover:bg-primary text-2xl p-5">Runs on a variety of hardware, but its execution provider interface also allows it to efficiently utilize accelerators specific to each hardware.</div>
        <div class="h-14 w-170 bg-gradient-to-r from-bg-base-200 to-cyan-500"></div>
        <div class="card bg-base-300 rounded-box grid h-200 w-100 place-items-center shadow-sm hover:bg-primary text-2xl p-5">Serves not only as a runtime engine but as a platform where many inference engines can be supported.</div>
        <div class="h-14 w-170 bg-gradient-to-r from-bg-base-200 to-cyan-500"></div>
    </div>
</div>
  </div>
  <div class="h-14 w-170 bg-gradient-to-r from-bg-base-200 to-cyan-500"></div>
</div>
