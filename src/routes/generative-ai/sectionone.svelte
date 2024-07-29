<script>
	import { quartInOut } from 'svelte/easing';
	import { fade } from 'svelte/transition';
	import { onMount } from 'svelte';
	import mobileExample from '../../images/mobile_example_1024_rect_cropped.png';
	import desktopExample from '../../images/desktop_example_1024_rect_cropped.png';
	import browserExample from '../../images/browser_example_1024_rect_cropped.png';

	let words = ['Mobile', 'Desktop', 'Browser'];
	let images = [
		mobileExample,
		desktopExample,
		browserExample
	];

	let currentWordIndex = 0;
	let currentWord = words[currentWordIndex];
	let currentImage = images[currentWordIndex];
	let show = true;

	onMount(() => {
		const interval = setInterval(() => {
			show = false;
			setTimeout(() => {
				currentWordIndex = (currentWordIndex + 1) % words.length;
				currentWord = words[currentWordIndex];
				currentImage = images[currentWordIndex];
				show = true;
			}, 1000);
		}, 3000);

		return () => clearInterval(interval);
	});
</script>

<div class="container mx-auto px-4 py-8">
	<h2 class="mb-8 text-4xl font-bold text-center card-title">Use ONNXRuntime - GenAI</h2>
	<div
		class="grid grid-cols-1 justify-items-center items-center p-4 lg:grid-cols-3 rounded-3xl bg-gray-300"
	>
		<div class="rounded-3xl card text-primary-content lg:col-span-2">
			<div class="card-body p-4">
				<div
					class="font-bold p-2 hover:border-black mx-auto rounded-3xl text-center text-2xl lg:w-2/3 transition duration-500 ease-in-out"
				>
					Run ONNX - GenAI on
					<br />
					{#if show}
						<span transition:fade={{ duration: 1000 }}>
							{currentWord}
						</span>
					{/if}
				</div>
			</div>
			{#key currentImage}
				<div class="mx-auto py-4 pl-4">
					{#if show}
						<span transition:fade={{ duration: 1000 }}>
							<img class="w-3/4 mx-auto" src={currentImage} alt="device" />
						</span>
					{/if}
				</div>
			{/key}
		</div>
		<div class="mx-auto pt-8 pr-20">
			<p class="text-lg">
				Want to try running <a
					href="https://onnxruntime.ai/docs/tutorials/"
					class="underline hover:text-blue-500 font-bold transition duration-500 ease-in-out"
					>these</a
				> yourself?
			</p>
			<p class="mt-2 text-lg font-bold p-4">Here's How!</p>
			<ul class="steps steps-vertical overflow-auto">
				<li class="step step-primary">Choose: Python, C#, C++, or JS</li>
				<li class="step step-primary text-left">Install for CPU</li>
				<li class="step text-left">Install for GPU (if needed)</li>
				<li class="step">Special Environment</li>
				<li class="step">Click the Install button below for more detailed instructions.</li>
			</ul>
			<a href="https://onnxruntime.ai/docs/install/">
				<div class="card-actions justify-end p-8">
					<button class="bg-primary btn btn-primary">Install</button>
				</div>
			</a>
		</div>
	</div>
</div>
