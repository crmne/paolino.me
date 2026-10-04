---
layout: post
title: "RubyLLM 2.0: Provider Tools for Web Search, Code Execution, and MCP"
date: 2026-10-14
description: "with_provider_tools lets the model search the web, run code, and call remote MCP servers on the provider's side, next to your own Ruby tools."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
image: /images/rubyllm-2.0-provider-tools.png
---
Your research assistant needs web search. You can write a search tool, pick a search API, sign up, store another key, and parse its results. Or you can let the model use the search service its provider already runs.

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5")
  .with_provider_tools(:web_search)

response = chat.ask "What is the latest stable Ruby version? Cite your source."
response.content
response.citations.filter_map(&:url).uniq
```

The provider runs the search during generation and returns the answer with its sources, without a search client or an extra key.

## Two Kinds of Tools, One Chat

Regular RubyLLM tools run your Ruby code in your process. Provider tools run on the provider's infrastructure. You can use both in the same chat:

```ruby
chat.with_tools(Weather)
    .with_provider_tools(:web_search, :code_execution)
```

The aliases make provider tools portable. `:web_search` becomes Anthropic's versioned search tool, OpenAI's Responses search tool, Gemini's Google Search grounding, and the equivalent tool on other providers, so you can switch models without changing the code.

The full set: `:web_search`, `:web_fetch` (or `:url_context`), `:x_search`, `:code_execution`, `:file_search`, `:image_generation`, `:apply_patch`, and `:mcp`.

Options use the provider's own vocabulary, because a lowest-common-denominator filter language would lose what each provider supports:

```ruby
chat.with_provider_tools(web_search: {
  allowed_domains: ["ruby-lang.org"],
  max_uses: 3
})
```

The alias works across providers, but those options are specific to one.

## Raw Definitions

Providers ship new tools faster than any library can wrap them, and I didn't want every new provider tool to require a RubyLLM release. You can pass a raw definition:

```ruby
chat.with_provider_tools({
  type: "tool_search_tool_regex_20251119",
  name: "tool_search"
})
```

A positional Hash goes into the payload as is. RubyLLM handles the response blocks the protocol returns, so you need a definition the endpoint accepts, not an alias in the gem.

## Remote MCP, Run by the Provider

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5")
  .with_provider_tools(mcp: {
    name: "docs",
    url: "https://learn.microsoft.com/api/mcp"
  })

chat.ask "Find the Azure Functions overview in Microsoft Learn."
```

The provider connects to the server, lists its tools, and calls them. Your process never opens a connection to it.

On OpenAI and Azure Responses, the provider can also stop and ask before each call. Those requests land in the same approval flow as your Ruby tools:

```ruby
chat = RubyLLM.chat(model: "gpt-5.6")
  .with_provider_tools(mcp: {
    name: "docs",
    url: "https://learn.microsoft.com/api/mcp",
    allowed_tools: ["microsoft_docs_search"],
    require_approval: "always"
  })

chat.ask "Search Microsoft documentation for Azure Blob Storage."
call = chat.pending_approvals.first
call.remote? # => true

chat.approve(call) # or chat.deny(call)
chat.complete
```

`remote?` tells you the provider will execute the call, not a Ruby tool. Your decision goes to the provider, and it works with streaming and without provider-side conversation storage.

If you'd rather your own process talk to MCP servers, with your own credentials and control over which tools the model sees, RubyLLM 2.1 adds a client for that: `RubyLLM::MCP` and `with_mcp`.

## See What the Model Did

Tool activity shows up on the response:

```ruby
response.server_tool_calls.each do |call|
  call.name
  call.input
  call.result
  call.raw # the provider's original block
end

response.citations
response.attachments            # generated images and files
response.tokens.server_tool_use # per-use counters the provider reports
```

Search results are the same `Citation` objects you get from document citations. Images from `:image_generation` or files from `:code_execution` come back as attachments.

Providers often bill tool uses on top of tokens, so a token-price estimate won't include every search. `server_tool_use` gives you the counts to price them yourself. (In 2.1 those counters share one name across providers, such as `"web_search_requests"`.)

## Follow-Up Questions

Some providers need their tool blocks replayed on later turns. Anthropic rejects a conversation that drops them. RubyLLM keeps them on the message and sends them back, streamed or not. When Anthropic pauses a long server-tool turn, RubyLLM continues it and hands you one combined response.

In Rails, the `server_tool_calls` and `raw_content` columns from the install and 2.0 upgrade generators keep all of that across requests. Declare the tools on an agent and they come back with the chat:

```ruby
class ResearchAgent < RubyLLM::Agent
  chat_model Chat
  model "claude-sonnet-5"
  provider_tools :web_search, :code_execution
end

ResearchAgent.find(chat_id).ask "And what changed since the previous release?"
```

## Provider Differences

Availability depends on the provider, model, and protocol. Ask for an alias a provider doesn't have and you get `RubyLLM::UnsupportedServerToolError` before any request, listing the ones it does. That includes DeepSeek's `:web_search`, because its endpoint silently ignores the tool.

A few tools need a non-default protocol. Mistral's hosted search and code execution want `protocol: :conversations`, Gemini's remote MCP wants `protocol: :interactions`, and OpenRouter's hosted shell and MCP want `protocol: :responses`:

```ruby
RubyLLM.chat(model: "mistral-small-latest", provider: :mistral, protocol: :conversations)
  .with_provider_tools(:web_search)
```

Not every provider can pause for MCP approval either. Anthropic runs allowed MCP calls immediately, so pick its tools with `default_config` and `configs` (2.1 also accepts `allowed_tools` there, and raises if you ask for approval Anthropic can't give). Gemini Interactions and xAI execute allowed tools automatically too.

Use your application code for application work and the provider's tools where they help, which mostly means search. The [provider tools guide](https://rubyllm.com/provider-tools/) has the per-provider tables, file search setup, and MCP connection details.
