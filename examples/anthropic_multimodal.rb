#!/usr/bin/env ruby
# frozen_string_literal: true

require './lib/smart_prompt'
require 'base64'

# Example: Multimodal (Text + Image) with Anthropic Claude
# This example demonstrates how to use Claude's vision capabilities

puts "=" * 60
puts "Anthropic Claude - Multimodal (Vision) Example"
puts "=" * 60

# Initialize the engine with Anthropic configuration
engine = SmartPrompt::Engine.new('config/anthropic_config.yml')

# Example 1: Analyze Image from URL
puts "\n1. Analyze Image from URL"
puts "-" * 60

SmartPrompt.define_worker :image_analyzer do
  use "claude"
  sys_msg("You are an expert at analyzing images and describing what you see in detail.")
  prompt(params[:message])
  send_msg
end

# Using a public image URL
image_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Cat03.jpg/400px-Cat03.jpg"

response = engine.call_worker(:image_analyzer, {
  message: [
    { type: "text", text: "What do you see in this image? Describe it in detail." },
    { type: "image_url", image_url: image_url }
  ]
})
puts "User: [Sends image URL: #{image_url}]"
puts "User: What do you see in this image? Describe it in detail."
puts "\nClaude: #{response}\n"

# Example 2: Analyze Local Image using Base64
puts "\n2. Analyze Local Image (Base64 Encoding)"
puts "-" * 60

# Check if local image exists
local_image_path = "./product_images/smartphone_1.png"

if File.exist?(local_image_path)
  # Read and encode image to base64
  image_data = File.binread(local_image_path)
  base64_image = Base64.strict_encode64(image_data)
  
  # Determine media type
  media_type = case File.extname(local_image_path).downcase
               when '.jpg', '.jpeg' then 'image/jpeg'
               when '.png' then 'image/png'
               when '.gif' then 'image/gif'
               when '.webp' then 'image/webp'
               else 'image/jpeg'
               end
  
  data_url = "data:#{media_type};base64,#{base64_image}"
  
  response = engine.call_worker(:image_analyzer, {
    message: [
      { type: "text", text: "Describe this product image. What features can you identify?" },
      { type: "image_url", image_url: data_url }
    ]
  })
  puts "User: [Sends local image: #{local_image_path}]"
  puts "User: Describe this product image. What features can you identify?"
  puts "\nClaude: #{response}\n"
else
  puts "Local image not found at #{local_image_path}"
  puts "Skipping base64 example.\n"
end

# Example 3: Multiple Images Analysis
puts "\n3. Compare Multiple Images"
puts "-" * 60

SmartPrompt.define_worker :image_comparator do
  use "claude"
  sys_msg("You are an expert at comparing and contrasting images.")
  prompt(params[:message])
  send_msg
end

image1_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Cat03.jpg/400px-Cat03.jpg"
image2_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4d/Cat_November_2010-1a.jpg/400px-Cat_November_2010-1a.jpg"

response = engine.call_worker(:image_comparator, {
  message: [
    { type: "text", text: "Compare these two images. What are the similarities and differences?" },
    { type: "image_url", image_url: image1_url },
    { type: "image_url", image_url: image2_url }
  ]
})
puts "User: [Sends two cat images]"
puts "User: Compare these two images. What are the similarities and differences?"
puts "\nClaude: #{response}\n"

# Example 4: Image + Text Context
puts "\n4. Image Analysis with Additional Context"
puts "-" * 60

SmartPrompt.define_worker :contextual_analyzer do
  use "claude"
  sys_msg("You are a product analyst helping with e-commerce listings.")
  prompt(params[:message])
  send_msg
end

product_image = "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c4/Smartphone.jpg/400px-Smartphone.jpg"

response = engine.call_worker(:contextual_analyzer, {
  message: [
    { type: "text", text: "This is a product image for our online store. Please:" },
    { type: "text", text: "1. Describe the product" },
    { type: "text", text: "2. Suggest a catchy product title" },
    { type: "text", text: "3. Write a brief product description (2-3 sentences)" },
    { type: "text", text: "4. List 3-5 key features" },
    { type: "image_url", image_url: product_image }
  ]
})
puts "User: [Sends product image with detailed instructions]"
puts "\nClaude: #{response}\n"

# Example 5: OCR and Text Extraction
puts "\n5. Text Extraction from Image (OCR)"
puts "-" * 60

SmartPrompt.define_worker :ocr_extractor do
  use "claude"
  sys_msg("You are an expert at reading and extracting text from images.")
  prompt(params[:message])
  send_msg
end

# Using an image with text (e.g., a sign or document)
text_image_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/8/87/PDF_file_icon.svg/400px-PDF_file_icon.svg.png"

response = engine.call_worker(:ocr_extractor, {
  message: [
    { type: "text", text: "Extract and transcribe any text you see in this image." },
    { type: "image_url", image_url: text_image_url }
  ]
})
puts "User: [Sends image with text]"
puts "User: Extract and transcribe any text you see in this image."
puts "\nClaude: #{response}\n"

# Example 6: Image Classification
puts "\n6. Image Classification and Categorization"
puts "-" * 60

SmartPrompt.define_worker :image_classifier do
  use "claude"
  sys_msg("You are an expert at categorizing and classifying images.")
  prompt(params[:message])
  send_msg
end

classify_image = "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Cat03.jpg/400px-Cat03.jpg"

response = engine.call_worker(:image_classifier, {
  message: [
    { type: "text", text: "Classify this image into categories. Provide:\n1. Main category\n2. Sub-categories\n3. Tags/keywords\n4. Suitable use cases" },
    { type: "image_url", image_url: classify_image }
  ]
})
puts "User: [Sends image for classification]"
puts "\nClaude: #{response}\n"

# Example 7: Image-based Question Answering
puts "\n7. Question Answering about Image Content"
puts "-" * 60

SmartPrompt.define_worker :image_qa do
  use "claude"
  sys_msg("You are helpful at answering questions about images.")
  prompt(params[:message])
  send_msg
end

qa_image = "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Cat03.jpg/400px-Cat03.jpg"

questions = [
  "What color is the animal?",
  "What is the animal doing?",
  "What is the setting or environment?"
]

questions.each_with_index do |question, index|
  response = engine.call_worker(:image_qa, {
    message: [
      { type: "image_url", image_url: qa_image },
      { type: "text", text: question }
    ]
  })
  puts "Q#{index + 1}: #{question}"
  puts "A#{index + 1}: #{response}\n"
end

puts "\n" + "=" * 60
puts "Multimodal examples completed!"
puts "=" * 60
puts "\nNote: Claude's vision capabilities work best with:"
puts "- Clear, well-lit images"
puts "- Images in JPEG, PNG, GIF, or WebP format"
puts "- Images up to 5MB in size"
puts "- Both URLs and base64-encoded images"
