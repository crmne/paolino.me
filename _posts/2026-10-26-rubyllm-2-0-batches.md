---
layout: post
title: "RubyLLM 2.0: Batches"
date: 2026-10-26
description: "Work that can wait can be cheaper. RubyLLM 2.0 submits chats and embeddings to provider batch APIs with the API you already use."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---
A user waiting for an answer needs an interactive request. An overnight job classifying ten thousand support tickets does not. Nobody is watching a spinner, and providers know it: Anthropic, OpenAI, Gemini, Vertex AI, Bedrock, Azure, Mistral, xAI, OpenRouter, and Cohere all have batch APIs, and the major ones charge a lot less for work you're willing to wait for.

Most apps leave that money on the table, because every batch API is its own little file format with its own upload, polling, and result-matching ritual.

In RubyLLM 2.0, it's the chat API you already know:

```ruby
chats = tickets.map do |ticket|
  RubyLLM.chat(model: "claude-haiku-4-5")
    .with_instructions("Classify this ticket as billing, bug, or feature request.")
    .ask_later(ticket.body)
end

batch = RubyLLM.batch(chats)
batch.id # save this
```

`ask_later` stages the question without sending anything. `RubyLLM.batch` submits all of them to the provider in one go. Instructions, history, tools, and schemas come along. You don't learn a second way to describe a request just because it runs overnight.

## Collect the Answers Later

Another process, another day, same batch:

```ruby
batch = RubyLLM::Batch.find(batch_id, provider: :anthropic)

if batch.refresh.complete?
  batch.messages.each do |message|
    message&.content # => "billing"
  end
end
```

`refresh` asks the provider for the latest state. `complete?` means processing has ended; `succeeded?`, `failed?`, and `cancelled?` tell you how. `batch.messages` comes back in submission order, so the first message answers the first ticket.

Requests can fail individually without sinking the batch. A failed slot is `nil` in `messages`, and `batch.statuses` tells you which slots succeeded, failed, or were cancelled. Resubmit the failures in a new batch, or finish them interactively with `chat.complete`.

If you still hold the chats you submitted, collecting appends each answer to its conversation. The chats come back complete and ready for a follow-up.

## Tools Work Too

A batch generates one model turn. If the model asks for a tool, run it locally and batch the next turn:

```ruby
batch.messages
chats.each(&:run_tools)

pending = chats.reject(&:complete?)
next_batch = RubyLLM.batch(pending) if pending.any?
```

That's the [agentic loop, exposed](/rubyllm-2-0-agentic-loop/), at batch prices: `generate` deferred for a thousand chats at once, `run_tools` in between.

## Rails Keeps Track

When every input is a persisted chat, RubyLLM saves the batch in its own table. You don't write a `Batch` model; your app keeps its `Chat` and `Message`, and RubyLLM owns the rest:

```ruby
chats = tickets.map do |ticket|
  Chat.create!(model: "claude-haiku-4-5").ask_later(ticket.body)
end

batch = RubyLLM.batch(chats)
BatchPollJob.perform_later(batch.id)
```

A job can then pick it up with nothing but the ID:

```ruby
class BatchPollJob < ApplicationJob
  def perform(batch_id)
    batch = RubyLLM::Batch.find(batch_id)
    return self.class.set(wait: 10.minutes).perform_later(batch_id) unless batch.refresh.complete?

    batch.messages
  end
end
```

RubyLLM restores the provider and the chats, then saves each answer through the same callbacks as a normal `ask`. Your broadcasts, your `after_create_commit` hooks, your usage records: all of it fires as if the user had been waiting. Run the job twice and you still get one answer per chat.

## Embeddings Batch Too

Backfilling embeddings for a product catalog is the other classic overnight job:

```ruby
requests = products.map do |product|
  RubyLLM.embed_later(product.description, model: "text-embedding-3-small")
end

batch = RubyLLM.batch(requests)
```

When it's done:

```ruby
products.zip(requests).each do |product, request|
  product.update!(embedding: request.result.vectors) if request.result
end
```

Collecting fills in each request's `result`. If you're collecting in another process, `batch.results` returns the embeddings in submission order, so store the product IDs in that order when you submit.

## The Cost Is the Batch Cost

The savings show up where you'd look for them:

```ruby
batch.cost.total
batch.messages.first&.cost&.total
```

`batch.cost` is the same `RubyLLM::Cost` you get everywhere else. When the provider reports what the batch cost, RubyLLM uses that. Otherwise it prices each result at batch rates, which on Anthropic, OpenAI, Gemini, Bedrock, Azure, and Mistral means half the interactive price. The total stays `nil` until processing ends, and missing prices stay unknown rather than turning into zero. In Rails, the batch cost survives being looked up from another process.

One fix worth knowing: on 2.0.0, batches from OpenAI reasoning models return a `nil` total because of how thinking tokens were priced. [Marc Köhlbrugge](https://github.com/marckohlbrugge) fixed that in 2.1.

## Where Providers Differ

Use one provider per batch. Anthropic and xAI accept mixed models in one batch; the others want one model per submission. Some batch endpoints are pickier than their interactive siblings: Bedrock takes no tools or structured output, Cohere no structured output. Bedrock and Vertex AI also need a storage bucket for the batch files. The [batch guide](https://rubyllm.com/batches/) has the full restriction table and setup.

Thanks to [@marckohlbrugge](https://github.com/marckohlbrugge), [@thomaswitt](https://github.com/thomaswitt), [@toddkummer](https://github.com/toddkummer), and [@khasinski](https://github.com/khasinski), whose requests and feedback shaped this.

I've always liked that batch APIs exist. I never liked using them. Now the cheap path is one method call away from the interactive one, and for work that can wait, there's no reason to pay full price.
