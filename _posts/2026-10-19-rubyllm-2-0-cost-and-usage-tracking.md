---
layout: post
title: "RubyLLM 2.0: Tokens, Costs, and the Usage Ledger"
date: 2026-10-19
description: "RubyLLM 2.0 counts every provider attempt, including retries, fallbacks, and cancelled streams, and reports a cost it can't establish as nil."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
image: /images/rubyllm-2.0-cost-and-usage.png
---
```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5").with_fallbacks("gpt-5.6")
response = chat.ask "Summarize this contract.", with: "contract.pdf"

response.tokens.input
response.tokens.output
response.tokens.cache_read
response.cost.total

chat.cost.total
```

The API looks the same as in 1.x. What changed in 2.0 is what those numbers include.

If the request to Claude was retried twice before it went through, all three attempts are in the response's accounting. If Claude gave up and `gpt-5.6` wrote the answer, the response accounts for the Claude attempts and the GPT one. If the user hits stop halfway through a stream and no assistant message is ever saved, the chat still accounts for whatever that stream reported before it stopped.

RubyLLM 2.0 records usage for each provider attempt, because your provider bills attempts, and one message can take several of them.

## What Each Total Includes

* `response.tokens` and `response.cost` add up every attempt that went into producing that response: retries, fallbacks, and the attempt that finally succeeded.
* `chat.tokens` and `chat.cost` add up every attempt the chat ever made, including cancelled ones with no message to show for it.
* `agent.cost` is its chat's total.

One-shot operations use the same objects:

```ruby
embedding = RubyLLM.embed("Ruby is a programmer's best friend")
embedding.tokens.input
embedding.cost.total

transcription = RubyLLM.transcribe("standup.m4a")
transcription.cost.total
```

## One Shape for Every Provider

Providers can't agree on whether cached tokens are part of the input count. Some include them, some report them separately. RubyLLM normalizes all of it before pricing, so the buckets mean the same thing everywhere:

| Reader | Counts |
| --- | --- |
| `tokens.input` | Ordinary input, excluding cache reads and writes |
| `tokens.output` | Billable output |
| `tokens.cache_read` | Input served from the prompt cache |
| `tokens.cache_write` | Input written to the prompt cache |
| `tokens.thinking` | Thinking tokens, when reported |

When a provider bills thinking as output, it's already in `tokens.output`. Don't add it twice. If a model prices thinking separately, `cost.thinking` carries that bucket.

`cost` mirrors the buckets with `cost.input`, `cost.output`, `cost.cache_read`, `cost.cache_write`, `cost.thinking`, and `cost.total`.

## Unknown Is Not Zero

If RubyLLM can't establish a number, it returns `nil`:

```ruby
chat.tokens.input # the counts the provider reported
chat.cost.total   # => nil if any attempt's cost is unknown
```

A cost is unknown when the model isn't in the pricing registry (your fine-tune, a model released this morning), or when an attempt may have been billed but the provider never sent usage: a timeout, a server error, a stream that died before its final usage event. The attempt's counts stay `nil`, and so does the aggregate total.

The exception is an attempt that provably wasn't billed. A refused connection, a failed TLS handshake, or a 4xx rejection before the model ran records zero and doesn't blank your totals.

A zero would make an unpriced model look free in your reports until someone noticed. A `nil` tells you the total is incomplete.

Some providers, such as OpenRouter and xAI, report the charge directly. `tokens.reported_cost` keeps that amount and `cost.total` prefers it over a registry estimate.

Provider tools that bill per use, like hosted web search, show up as counters on `tokens.server_tool_use`, for example `{"web_search_requests" => 2}`. A counter isn't a price, so unless the provider reports the charge, `cost.total` covers tokens only and you add the searches at your provider's rate.

## The Rails Ledger

With `acts_as_chat`, every finished attempt is written to `ruby_llm_usages` before the assistant message callback runs. A cancelled stream leaves an accounting row even when it leaves no message.

You don't add a model for it. Your app owns `Chat` and `Message`; RubyLLM owns the ledger table and reads it for you:

```ruby
chat = Chat.find(params[:id])
chat.cost.total
chat.messages.last.tokens.output
```

Each row stores the operation, provider, model, status (`succeeded`, `failed`, or `cancelled`), the token buckets, and decimal cost columns. Costs are frozen when the attempt finishes. A later `RubyLLM.models.refresh` updates prices for new requests and never rewrites last month.

That makes the table good for reporting. Mind one thing: SQL `SUM` skips `NULL`, so a sum of known costs looks like a complete bill even when it isn't. Count the unpriced attempts next to it:

```sql
SELECT model,
       SUM(total_cost) AS known_cost,
       SUM(CASE WHEN total_cost IS NULL THEN 1 ELSE 0 END) AS unpriced_attempts
FROM ruby_llm_usages
WHERE created_at >= '2026-10-01'
GROUP BY model;
```

Since frozen costs only use the prices RubyLLM knew at the time, refresh the registry on a schedule. A daily job is plenty:

```ruby
# lib/tasks/ruby_llm.rake
namespace :ruby_llm do
  task refresh_models: :environment do
    RubyLLM.models.refresh
  end
end
```

If you're upgrading from 1.16, the upgrade generator backfills one succeeded usage row for each historical message that recorded usage, then removes the old token and cost columns in a later cleanup step. It can't reconstruct retries 1.x never stored, and it doesn't invent costs for rows that never had one.

## Send the Attempts Elsewhere

Every finished attempt also emits `usage.ruby_llm`, with `operation`, `provider`, `model`, `status`, `tokens`, and `cost`:

```ruby
ActiveSupport::Notifications.subscribe("usage.ruby_llm") do |event|
  payload = event.payload

  Metrics.increment("llm.attempt", tags: {
    provider: payload[:provider],
    model: payload[:model],
    status: payload[:status]
  })
  Metrics.distribution("llm.cost", payload[:cost].total) if payload[:cost].total
end
```

It fires for embeddings, images, speech, transcription, moderation, OCR, and reranking too, and for failed attempts that raised before returning anything. You don't need to subscribe for `chat.cost` to work. The event is there for metrics, billing, or finance systems that need the same data.

RubyLLM 2.1 takes the ledger further: one-shot operations get rows of their own, attributed to a user or account, and provider tool counts are stored with each attempt.

The [Tokens and Costs guide](https://rubyllm.com/cost-and-usage-tracking/) covers pricing usage yourself with `cost_for`, long-context tiers, and the rest of the details.
