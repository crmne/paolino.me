---
layout: post
title: "RubyLLM 2.0: Prompt Caching"
date: 2026-10-23
description: "Stop paying full price for the same prompt prefix. RubyLLM 2.0 adds with_caching, cache_until_here, and Gemini cache resources."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---
Look at what an agent sends on each turn. Turn one: system prompt, tool definitions, a 40-page contract, a question. Turn two: the same system prompt, the same tools, the same contract, the first answer, a tool result, a slightly different question. By turn twenty you've paid for that contract twenty times.

Prompt caching lets the provider reuse a prefix it has already processed and bill the cache read at a fraction of normal input. RubyLLM 2.0 gives it one API:

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5").with_caching
chat.with_instructions(review_guidelines)

response = chat.ask "Review this migration.", with: "db/migrate/20261001_add_billing.rb"
response.tokens.cache_write # first request: the prefix goes into the cache

response = chat.ask "Now check the rollback."
response.tokens.cache_read  # later requests: read back at the cache rate
```

Most apps need nothing more. Turn it on for workloads that repeat a long prefix (agent loops, many questions about one document, a big system prompt shared across users) and the provider does the rest.

The providers still set the rules: minimum prefix length, how long the cache lives, which models support it. A cache hit is never guaranteed. RubyLLM's job is to send the right controls and tell you what happened.

## One Method, Many Dialects

Anthropic wants `cache_control` markers on content blocks. Bedrock Converse wants cache points. OpenAI-compatible APIs take a `prompt_cache_key`. OpenAI and Gemini also cache on their own, and Gemini has cache resources you manage yourself. `with_caching` translates to each of them, so none of that ends up in application code.

Options set the TTL, the cache key, and the mode:

```ruby
chat.with_caching(ttl: "1h")                     # Anthropic, Bedrock, OpenRouter, supported OpenAI models
chat.with_caching(key: "repo:#{repository.id}")  # OpenAI-compatible APIs and Mistral
chat.with_caching(mode: "explicit")              # supported OpenAI-compatible models
```

Calling `with_caching` again replaces the policy. Agents get the same thing as a macro:

```ruby
class CodeReviewer < RubyLLM::Agent
  model "claude-sonnet-5"
  caching ttl: "1h"
end
```

To stop RubyLLM from sending cache controls, pass `false`:

```ruby
chat.with_caching(false)
```

That turns off RubyLLM's caching instructions. It can't turn off caching a provider does on its own.

## Mark Where the Stable Part Ends

Automatic caching guesses where your reusable prefix ends. Sometimes you know exactly:

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5").with_caching(ttl: "1h")

chat.with_instructions(analysis_prompt).cache_until_here
chat.add_message(role: :user, content: contract_text).cache_until_here

chat.ask "Does clause 14 conflict with the termination terms in clause 3?"
chat.ask "Which clauses mention liability caps?"
```

`cache_until_here` marks the latest message as a cache boundary. Combined with `with_caching`, RubyLLM sends both: your explicit boundaries for the prompt and the contract, and automatic caching for the conversation growing after them.

Anthropic, OpenRouter, Bedrock Converse, and selected OpenAI-compatible models understand boundaries. Providers that don't simply keep their own caching behavior, so the same code runs everywhere.

In Rails, the boundary is a `cache_until_here` column on the message, so it's replayed with the conversation every time the chat is loaded:

```ruby
chat = Chat.create!(model: "claude-sonnet-5")
chat.with_caching(ttl: "1h")
chat.with_instructions(analysis_prompt).cache_until_here
chat.add_message(role: :user, content: contract_text).cache_until_here
```

Whether you ask about that contract from a controller or from a background job days later, the boundary is still there.

## Gemini Caches You Own

Gemini and Vertex AI also let you create a cache as a resource, with a name and an expiry, and point any number of chats at it:

```ruby
cache = RubyLLM.cache(
  File.read("handbook.md"),
  model: "gemini-3.7-flash",
  instructions: "Answer questions using the employee handbook.",
  ttl: 3600
)

chat = RubyLLM.chat(model: "gemini-3.7-flash").with_caching(id: cache)
chat.ask "What's the expense approval process?"
```

Save `cache.name` and find it again from another process with `RubyLLM::CachedContent.find(name, provider: :gemini)` (or `:vertexai`). `cache.renew(ttl: 7200)` extends it and `cache.delete` drops it early.

One Gemini rule to know: a request that uses a cache can't also send its own system instructions or tools. Put the instructions in the cache, as above, and leave `with_instructions` off the chat.

## Check the Receipt

Writing to a cache can cost more than plain input, so caching a prefix you never reuse costs more than not caching it. Check the buckets:

```ruby
response.tokens.cache_write
response.tokens.cache_read

response.cost.cache_write
response.cost.cache_read
response.cost.total
```

RubyLLM normalizes cache reads and writes into their own buckets on every provider and prices each one from the model registry. In Rails they're recorded per attempt with the rest of your usage, so you can answer "did caching pay off this month?" with a query.

Thanks to [@arunkumarry](https://github.com/arunkumarry), whose issue and pull request for Anthropic and Bedrock caching got this started.

The [prompt caching guide](https://rubyllm.com/prompt-caching/) has the per-provider option table and the full cache lifecycle. Start with your most repetitive workload and check `cache_read` and the cache costs.
