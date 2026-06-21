#!/usr/bin/env ruby
# frozen_string_literal: true

require './lib/smart_prompt'
require 'json'

# Example: Tool Calling (Function Calling) with Anthropic Claude
# This example demonstrates how to use Claude with external tools/functions

puts "=" * 60
puts "Anthropic Claude - Tool Calling Example"
puts "=" * 60

# Initialize the engine with Anthropic configuration
engine = SmartPrompt::Engine.new('config/anthropic_config.yml')

# Example 1: Simple Weather Tool
puts "\n1. Simple Weather Tool"
puts "-" * 60

# Define the weather tool
weather_tool = [
  {
    type: "function",
    function: {
      name: "get_weather",
      description: "Get the current weather for a specific location",
      parameters: {
        type: "object",
        properties: {
          location: {
            type: "string",
            description: "The city and state, e.g. San Francisco, CA"
          },
          unit: {
            type: "string",
            enum: ["celsius", "fahrenheit"],
            description: "The temperature unit to use"
          }
        },
        required: ["location"]
      }
    }
  }
]

SmartPrompt.define_worker :weather_assistant do
  use "claude"
  sys_msg("You are a helpful weather assistant. Use the get_weather tool when users ask about weather.")
  prompt(params[:message])
  params.merge(tools: weather_tool)
  send_msg
end

response = engine.call_worker(:weather_assistant, {
  message: "What's the weather like in Tokyo?"
})
puts "User: What's the weather like in Tokyo?"
puts "Claude: #{response}\n"

# Example 2: Multiple Tools - Calculator
puts "\n2. Calculator Tools"
puts "-" * 60

calculator_tools = [
  {
    type: "function",
    function: {
      name: "add",
      description: "Add two numbers together",
      parameters: {
        type: "object",
        properties: {
          a: { type: "number", description: "First number" },
          b: { type: "number", description: "Second number" }
        },
        required: ["a", "b"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "multiply",
      description: "Multiply two numbers",
      parameters: {
        type: "object",
        properties: {
          a: { type: "number", description: "First number" },
          b: { type: "number", description: "Second number" }
        },
        required: ["a", "b"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "divide",
      description: "Divide two numbers",
      parameters: {
        type: "object",
        properties: {
          a: { type: "number", description: "Numerator" },
          b: { type: "number", description: "Denominator" }
        },
        required: ["a", "b"]
      }
    }
  }
]

SmartPrompt.define_worker :calculator_assistant do
  use "claude"
  sys_msg("You are a helpful calculator assistant. Use the available math tools to help users with calculations.")
  prompt(params[:message])
  params.merge(tools: calculator_tools)
  send_msg
end

response = engine.call_worker(:calculator_assistant, {
  message: "What is 15 multiplied by 23, then divided by 5?"
})
puts "User: What is 15 multiplied by 23, then divided by 5?"
puts "Claude: #{response}\n"

# Example 3: Database Query Tool
puts "\n3. Database Query Tool"
puts "-" * 60

database_tools = [
  {
    type: "function",
    function: {
      name: "query_database",
      description: "Query the customer database for information",
      parameters: {
        type: "object",
        properties: {
          query_type: {
            type: "string",
            enum: ["customer_info", "order_history", "product_details"],
            description: "The type of query to perform"
          },
          customer_id: {
            type: "string",
            description: "The customer ID to query"
          },
          filters: {
            type: "object",
            description: "Additional filters for the query"
          }
        },
        required: ["query_type"]
      }
    }
  }
]

SmartPrompt.define_worker :database_assistant do
  use "claude"
  sys_msg("You are a customer service assistant with access to the customer database. Use the query_database tool to help users.")
  prompt(params[:message])
  params.merge(tools: database_tools)
  send_msg
end

response = engine.call_worker(:database_assistant, {
  message: "Can you look up the order history for customer ID 12345?"
})
puts "User: Can you look up the order history for customer ID 12345?"
puts "Claude: #{response}\n"

# Example 4: File Operations Tool
puts "\n4. File Operations Tool"
puts "-" * 60

file_tools = [
  {
    type: "function",
    function: {
      name: "read_file",
      description: "Read the contents of a file",
      parameters: {
        type: "object",
        properties: {
          file_path: {
            type: "string",
            description: "The path to the file to read"
          }
        },
        required: ["file_path"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "write_file",
      description: "Write content to a file",
      parameters: {
        type: "object",
        properties: {
          file_path: {
            type: "string",
            description: "The path to the file to write"
          },
          content: {
            type: "string",
            description: "The content to write to the file"
          }
        },
        required: ["file_path", "content"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "list_files",
      description: "List files in a directory",
      parameters: {
        type: "object",
        properties: {
          directory: {
            type: "string",
            description: "The directory path to list files from"
          }
        },
        required: ["directory"]
      }
    }
  }
]

SmartPrompt.define_worker :file_assistant do
  use "claude"
  sys_msg("You are a helpful file management assistant. Use the available file tools to help users manage their files.")
  prompt(params[:message])
  params.merge(tools: file_tools)
  send_msg
end

response = engine.call_worker(:file_assistant, {
  message: "Can you list all files in the /documents folder?"
})
puts "User: Can you list all files in the /documents folder?"
puts "Claude: #{response}\n"

# Example 5: API Integration Tool
puts "\n5. API Integration Tool"
puts "-" * 60

api_tools = [
  {
    type: "function",
    function: {
      name: "fetch_stock_price",
      description: "Fetch the current stock price for a given ticker symbol",
      parameters: {
        type: "object",
        properties: {
          ticker: {
            type: "string",
            description: "The stock ticker symbol (e.g., AAPL, GOOGL)"
          }
        },
        required: ["ticker"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "fetch_news",
      description: "Fetch recent news articles about a company or topic",
      parameters: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "The search query for news articles"
          },
          limit: {
            type: "number",
            description: "Maximum number of articles to return"
          }
        },
        required: ["query"]
      }
    }
  }
]

SmartPrompt.define_worker :market_assistant do
  use "claude"
  sys_msg("You are a financial market assistant. Use the available tools to provide stock prices and news.")
  prompt(params[:message])
  params.merge(tools: api_tools)
  send_msg
end

response = engine.call_worker(:market_assistant, {
  message: "What's the current price of Apple stock and any recent news about the company?"
})
puts "User: What's the current price of Apple stock and any recent news about the company?"
puts "Claude: #{response}\n"

# Example 6: Complex Tool with Nested Parameters
puts "\n6. Complex Tool with Nested Parameters"
puts "-" * 60

search_tool = [
  {
    type: "function",
    function: {
      name: "search_products",
      description: "Search for products in the catalog with advanced filters",
      parameters: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "The search query"
          },
          filters: {
            type: "object",
            properties: {
              category: {
                type: "string",
                description: "Product category"
              },
              price_range: {
                type: "object",
                properties: {
                  min: { type: "number", description: "Minimum price" },
                  max: { type: "number", description: "Maximum price" }
                }
              },
              in_stock: {
                type: "boolean",
                description: "Only show in-stock items"
              }
            }
          },
          sort_by: {
            type: "string",
            enum: ["price_asc", "price_desc", "popularity", "newest"],
            description: "How to sort the results"
          }
        },
        required: ["query"]
      }
    }
  }
]

SmartPrompt.define_worker :shopping_assistant do
  use "claude"
  sys_msg("You are a helpful shopping assistant. Use the search_products tool to help users find products.")
  prompt(params[:message])
  params.merge(tools: search_tool)
  send_msg
end

response = engine.call_worker(:shopping_assistant, {
  message: "Find me laptops under $1000 that are in stock, sorted by popularity"
})
puts "User: Find me laptops under $1000 that are in stock, sorted by popularity"
puts "Claude: #{response}\n"

# Example 7: Tool Calling Best Practices
puts "\n7. Tool Calling Best Practices"
puts "-" * 60

puts "Best Practices for Tool Calling with Claude:"
puts "1. Provide clear, descriptive function names"
puts "2. Write detailed descriptions for functions and parameters"
puts "3. Use appropriate parameter types (string, number, boolean, object, array)"
puts "4. Mark required parameters explicitly"
puts "5. Use enums for parameters with limited valid values"
puts "6. Include examples in parameter descriptions when helpful"
puts "7. Keep tool definitions focused and single-purpose"
puts "8. Test tools with various user queries"
puts "9. Handle tool errors gracefully in your implementation"
puts "10. Consider tool execution order for complex workflows\n"

puts "\n" + "=" * 60
puts "Tool calling examples completed!"
puts "=" * 60
puts "\nNote: These examples show tool definitions. In a real application,"
puts "you would implement the actual tool functions and handle the tool"
puts "calls returned by Claude to execute the requested operations."
