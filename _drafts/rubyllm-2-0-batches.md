---
layout: post
title: "Discounted Batch Processing in RubyLLM 2.0"
description: "Stage chats and embeddings, submit provider batches, and collect results with batch pricing and Rails persistence in RubyLLM 2.0."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

A user waiting for an answer needs an interactive request. An overnight job classifying ten thousand tickets can wait, and several providers charge less when you submit that work as a batch.

RubyLLM 2.0 lets you build those requests with the chat API you already use:

```ruby
chats = documents.map do |doc|
  RubyLLM.chat(model: "claude-haiku-4-5")
    .with_instructions("Summarize the document in one paragraph.")
    .ask_later(doc.text)
end

batch = RubyLLM.batch(chats)
batch.id
```

`ask_later` stages each question locally. `RubyLLM.batch` submits them to the provider. That's the part I'm pleased with: you don't have to learn a second way to describe a model request just to run it overnight.

## Collect the Answers Later

Keep the batch ID and provider so another process can look it up:

```ruby
batch = RubyLLM::Batch.find(batch_id, provider: :anthropic)
batch.refresh

if batch.complete?
  messages = batch.messages
end
```

`complete?` means processing has ended. `succeeded?`, `failed?`, and `cancelled?` distinguish the outcome. `refresh` contacts the provider; the predicates read the last known state.

`messages` returns results in submission order. A failed request occupies a `nil` slot, and `batch.statuses` gives the individual outcomes. You can retry those requests separately.

When RubyLLM still has the submitted chats, collecting appends each successful response to its conversation. A response may contain tool calls, so collecting doesn't necessarily finish the conversation. Run those tools locally with `run_tools`, then batch the next model turn if you want to continue at batch rates.

Use one provider per batch. Anthropic and xAI allow mixed models; the other integrations require one model per submission. Choose a model with batch access. Some batch endpoints restrict tools, structured output, or attachments; the [batch guide](https://rubyllm.com/next/batches/#provider-restrictions) lists those differences.

## Rails Keeps the Batch State

When all the inputs are persisted chats, RubyLLM saves the batch state in its own table:

```ruby
chats = tickets.map do |ticket|
  Chat.create!(model: "claude-haiku-4-5").ask_later(ticket.body)
end

batch = RubyLLM.batch(chats)
BatchPollJob.perform_later(batch.id)
```

A later job can collect using only the ID:

```ruby
class BatchPollJob < ApplicationJob
  def perform(batch_id)
    batch = RubyLLM::Batch.find(batch_id)

    unless batch.refresh.complete?
      self.class.set(wait: 10.minutes).perform_later(batch_id)
      return
    end

    batch.messages
  end
end
```

RubyLLM restores the stored provider and chat references, then persists the responses through the same callbacks as synchronous chat. Collecting an already-applied response again doesn't append a duplicate.

Your app keeps its `Chat` and `Message` models. It doesn't need an application `Batch` model just to track the provider's job.

## Embeddings Batch Too

Backfilling a product catalog is another good fit. Stage embedding requests with the same model and provider:

```ruby
requests = products.map do |product|
  RubyLLM.embed_later(product.description, model: "text-embedding-3-small")
end

batch = RubyLLM.batch(requests)
batch_id = batch.id
```

Later:

```ruby
batch = RubyLLM::Batch.find(batch_id, provider: :openai)

if batch.refresh.complete?
  embeddings = batch.results
  embeddings.first&.vectors
end
```

Persist your product IDs in submission order so you can match results back to records. If you still have the staged request objects, collecting also fills each request's `result`.

## The Cost Uses the Batch Rate

RubyLLM freezes the batch cost when it collects each successful result:

```ruby
batch.cost.total
batch.messages.first&.cost&.total
```

`batch.cost` is a `RubyLLM::Cost`, just like a message or embedding cost. Its total stays `nil` until processing ends. An exact provider-reported batch charge takes precedence; otherwise it adds the collected results at available batch rates. Missing pricing stays unknown. A charge for the whole batch is not divided among its individual results.

Batch rates and turnaround targets depend on the provider and model. The [batch guide](https://rubyllm.com/next/batches/) covers setup, including cloud storage for services that need it.

For work that can wait, I'm glad the cheaper API is now as easy to use as the interactive one.
