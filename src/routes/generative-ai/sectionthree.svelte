<script>
	import tableGenerationVideo from '../../images/table-generation.mp4';
</script>
<div class="container ms-auto">
	<div class="flex justify-center mx-auto">
		<div class="card mx-auto" style=" background-color: #CBCBCB; border: 4px solid #A2E5FC;">
			<div class="card-body mx-auto">
				<div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
					<!-- Left Content -->
					<div class="">
						<h2 class="card-title text-left mb-14 text-5xl flex flex-col items-center">
							Understanding Generative AI
						</h2>
						<p style="line-height: 2.5; text-align: center; text-indent: 40px;">
							In the hands of businesses and users, Generative AI is a tool that transforms ideas
							into new content from existing data, unlocking endless possibilities for
							personalization and growth. This innovative technology serves as a catalyst for
							creativity, enabling the generation of unique and tailored experiences that resonate
							with audiences. It's a bridge between imagination and reality, turning abstract
							concepts into tangible assets that drive engagement and success. Additionally,
							Generative AI can enhance customer satisfaction by providing personalized
							recommendations and solutions. It also fosters innovation by enabling rapid
							prototyping and experimentation, allowing businesses to stay ahead in a competitive
							market.
						</p>
					</div>

					<!-- Right Content -->
					<div class="mx-auto items-center">
						<div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 justify-between mb-4">
							<button
								class="btn btn-primary"
								onclick="location.href='https://huggingface.co/models?other=llama'"
								style="background-color: #A2E5FC; border-radius: 20px; flex: 1; white-space: nowrap;"
								>LLaMa</button
							>
							<button
								class="btn btn-primary"
								onclick="location.href='https://huggingface.co/models?other=gpt_neo'"
								style="background-color: #A2E5FC; border-radius: 20px; flex: 1; white-space: nowrap;"
								>GPT Neo</button
							>
							<button
								class="btn btn-primary"
								onclick="location.href='https://huggingface.co/models?other=bloom'"
								style="background-color: #A2E5FC; border-radius: 20px; flex: 1; white-space: nowrap;"
								>BLOOM</button
							>
							<button
								class="btn btn-primary"
								onclick="location.href='https://huggingface.co/models?other=opt'"
								style="background-color: #A2E5FC; border-radius: 20px; flex: 1; white-space: nowrap;"
								>OPT</button
							>
							<button
								class="btn btn-primary"
								onclick="location.href='https://huggingface.co/models?other=gpt-j'"
								style="background-color: #A2E5FC; border-radius: 20px; flex: 1; white-space: nowrap;"
								>GPT-J</button
							>
							<button
								class="btn btn-primary"
								onclick="location.href='https://huggingface.co/models?other=flan-t5'"
								style="background-color: #A2E5FC; border-radius: 20px; flex: 1; white-space: nowrap;"
								>FLAN-T5</button
							>
						</div>
						<div class="">
							<video
								autoplay
								loop
								controls
								style="border: 6px solid black; border-bottom-left-radius: 17px; border-bottom-right-radius: 17px;"
							>
								<source src={tableGenerationVideo} type="video/mp4" />
								<track kind="captions" />
							</video>
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
</div>
