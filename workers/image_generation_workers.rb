# Image Generation Workers for SmartPrompt
#
# These workers wrap the SiliconFlow image generation API exposed by
# ImageGenerationAdapter (POST /v1/images/generations). All of them expect an
# `image_gen` LLM to be configured in the engine, e.g.:
#
#   image_gen:
#     adapter: "image_generation"
#     url: "https://api.siliconflow.cn/v1/"
#     api_key: ENV["SILICONFLOW_API_KEY"]
#     model: "Kwai-Kolors/Kolors"

# Text-to-image generation worker.
#
# Recognized params:
#   prompt:, model:, negative_prompt:,
#   image_size: (alias size:), batch_size: (alias n:),
#   seed:, num_inference_steps:, guidance_scale:, cfg:,
#   save_to_file:, output_dir:, filename_prefix:
SmartPrompt.define_worker :image_generator do
  use "image_gen"

  images = generate_image(params[:prompt], {
    model: params[:model],
    negative_prompt: params[:negative_prompt],
    image_size: params[:image_size] || params[:size],
    batch_size: params[:batch_size] || params[:n],
    seed: params[:seed],
    num_inference_steps: params[:num_inference_steps],
    guidance_scale: params[:guidance_scale],
    cfg: params[:cfg],
  })

  if params[:save_to_file]
    saved_files = save_image(images, params[:output_dir] || "./generated_images", params[:filename_prefix] || "generated")
    { images: images, saved_files: saved_files }
  else
    images
  end
end

# Image editing / image-to-image worker (for Qwen/Qwen-Image-Edit-* and similar).
#
# Recognized params:
#   prompt:, model:, image: (alias image_file:), image2:, image3:,
#   negative_prompt:, seed:, cfg:,
#   save_to_file:, output_dir:, filename_prefix:
SmartPrompt.define_worker :image_editor do
  use "image_gen"

  images = edit_image(params[:prompt], {
    model: params[:model],
    image: params[:image] || params[:image_file],
    image2: params[:image2],
    image3: params[:image3],
    negative_prompt: params[:negative_prompt],
    seed: params[:seed],
    cfg: params[:cfg],
  })

  if params[:save_to_file]
    saved_files = save_image(images, params[:output_dir] || "./edited_images", params[:filename_prefix] || "edited")
    { images: images, saved_files: saved_files }
  else
    images
  end
end

# Creative art generation worker. Appends the requested art style to the prompt
# before generating.
SmartPrompt.define_worker :art_generator do
  use "image_gen"

  prompt = params[:prompt] || "A beautiful artistic creation"
  prompt = "#{prompt}, in the style of #{params[:art_style]}" if params[:art_style]

  images = generate_image(prompt, {
    model: params[:model],
    negative_prompt: params[:negative_prompt],
    image_size: params[:image_size] || params[:size],
    batch_size: params[:batch_size] || params[:n],
    seed: params[:seed],
    num_inference_steps: params[:num_inference_steps],
    guidance_scale: params[:guidance_scale],
    cfg: params[:cfg],
  })

  if params[:save_to_file]
    saved_files = save_image(images, params[:output_dir] || "./art_images", params[:filename_prefix] || "art")
    { images: images, saved_files: saved_files }
  else
    images
  end
end

# Product photography worker. Enhances the prompt with studio-photo wording.
SmartPrompt.define_worker :product_image_generator do
  use "image_gen"

  prompt = "Professional product photography, studio lighting, clean background, high detail, #{params[:prompt]}"

  images = generate_image(prompt, {
    model: params[:model],
    negative_prompt: params[:negative_prompt] || "blurry, low quality, distorted",
    image_size: params[:image_size] || params[:size],
    batch_size: params[:batch_size] || params[:n],
    seed: params[:seed],
    num_inference_steps: params[:num_inference_steps],
    guidance_scale: params[:guidance_scale],
    cfg: params[:cfg],
  })

  if params[:save_to_file]
    saved_files = save_image(images, params[:output_dir] || "./product_images", params[:filename_prefix] || "product")
    { images: images, saved_files: saved_files }
  else
    images
  end
end
