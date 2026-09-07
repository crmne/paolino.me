---
layout: post
title: "Web Search, Code Execution, and MCP in RubyLLM 2.0"
description: "Enable provider web search and code execution with with_server_tools, read their results, and use raw tool definitions in RubyLLM 2.0."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

A research assistant needs web search. You can write a search tool yourself, or let the model use the search service its provider already runs.

RubyLLM 2.0 supports the second option:

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5")
  .with_server_tools(:web_search)

response = chat.ask "What is the latest stable Ruby version? Cite your source."
response.content
response.citations.map(&:url).compact.uniq
```

The provider runs the search during generation. Your Ruby process receives the answer and its sources.

## Enable the Tools You Need

Regular RubyLLM tools execute your Ruby code. Server tools execute on the provider's infrastructure. You can use both in the same chat:

```ruby
chat.with_tools(Weather)
chat.with_server_tools(:web_search, :code_execution)
```

RubyLLM translates the aliases for the selected protocol. `:web_search` becomes Anthropic's versioned search tool, OpenAI's Responses search tool, Gemini's Google Search grounding, and the corresponding tool on other supported providers.

Other aliases include `:web_fetch`, `:file_search`, `:image_generation`, and `:mcp`. Availability depends on the provider and protocol. An unsupported alias raises `RubyLLM::UnsupportedServerToolError` with the names that provider does support.

Most of these tools work through the provider's default protocol. A few need an explicit selection: DeepSeek uses `protocol: :responses` for search, for example. The [server tools guide](https://rubyllm.com/next/server-tools/#protocol-selection) lists those choices.

Options use the provider's own vocabulary. For Anthropic:

```ruby
chat.with_server_tools(web_search: {
  allowed_domains: ["ruby-lang.org"],
  max_uses: 3
})
```

The alias is portable; those options aren't automatically translated for another provider.

## Use a New Tool Without Waiting for a Release

I didn't want every new provider tool to require a RubyLLM release. You can pass its definition directly:

```ruby
chat.with_server_tools({
  type: "tool_search_tool_regex_20251119",
  name: "tool_search"
})
```

A positional hash goes through as the provider's tool definition. RubyLLM puts it in the payload and handles the supported protocol's response blocks. You still need a definition the chosen endpoint accepts, but you don't need an alias in the gem first.

## Connect a Remote MCP Server

```ruby
chat = RubyLLM.chat(model: "gpt-5.4")
  .with_server_tools(mcp: {
    name: "microsoft_docs",
    url: "https://learn.microsoft.com/api/mcp"
  })
```

The provider calls the remote server. On OpenAI and Azure Responses, MCP calls can use the same `pending_approvals`, `approve`, and `deny` API as Ruby tools. `call.remote?` identifies a provider-executed call. No provider-side conversation storage is needed for that approval flow.

## Read What the Model Did

Where the protocol returns tool blocks, they appear on `response.server_tool_calls`:

```ruby
response.server_tool_calls.each do |call|
  call.type
  call.name
  call.input
  call.result
  call.raw
end
```

The fields depend on the block. An invocation can have input and no result; another block can carry the result. `raw` preserves the provider's original block.

OpenRouter exposes its search work through citations and usage counters, so `server_tool_calls` can be empty even when search ran. Read sources through `response.citations`.

## Continue the Conversation

Some providers require those tool blocks to be replayed on later turns. Anthropic rejects a conversation that leaves them out. RubyLLM preserves and replays them, including when the answer was streamed.

Anthropic can also pause a long server-tool turn. RubyLLM continues it and combines the segments into the response you receive.

In Rails, the install and upgrade generators provide the `server_tool_calls` and `raw_content` columns needed to save this information. Define tools on an agent to reapply the configuration when loading a chat:

```ruby
class ResearchAgent < RubyLLM::Agent
  chat_model Chat
  model "claude-sonnet-5"
  server_tools :web_search, :code_execution
end
```

Provider tool charges can be separate from token costs. Counters such as `response.tokens.server_tool_use` show reported usage; don't assume a token-price estimate includes every search or sandbox charge.

I'm glad this fits beside Ruby tools without another client to configure. Use your application code for application work and the provider's tools where they help. The [server tools guide](https://rubyllm.com/next/server-tools/) has the alias table and MCP examples.
