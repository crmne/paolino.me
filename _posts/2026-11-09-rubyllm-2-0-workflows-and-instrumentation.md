---
layout: post
title: "RubyLLM 2.0: Workflows Without a Workflow Engine"
date: 2026-11-09
description: "RubyLLM.workflow names a task and its steps so every model call, tool call, and usage event can be traced back to it. Your control flow stays Ruby."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM, Observability]
---

A research agent calls a model, searches the web a few times, and hands its notes to a writing agent. The Ruby is short, but the logs show dozens of separate events with nothing tying them to the article they produced.

RubyLLM 2.0 lets you name the work:

```ruby
RubyLLM.workflow("Write article", id: "article-42") do |workflow|
  notes = workflow.step("Research") do
    ResearchAgent.new.ask(topic).content
  end

  workflow.step("Draft") do
    WriterAgent.new.ask(notes).content
  end
end
```

Every RubyLLM event inside that block now carries `workflow_id` and `workflow_name`. Inside a step, it also carries `workflow_step_id` and `workflow_step_name`. Model calls, tool calls, and usage rows for retries are all tagged, so you can group them.

The blocks return their normal values, so `notes` is a String and the rest of your code stays the same.

## Why Not a Workflow Engine

Many AI frameworks come with a graph DSL: nodes, edges, a state object, and a runtime that executes it for you. In Ruby you already have all the control flow you need: a sequence is method calls, a branch is a `case`, a retry is `retry`. What's missing is a way to see that control flow afterwards, and that's all `RubyLLM.workflow` does.

`workflow.step` runs your block and adds context to the events inside it. It doesn't persist progress, schedule anything, or retry. Branches, loops, error handling, and concurrency stay in your code, where you can read them. For durability, use [the agentic loop's verbs](/rubyllm-2-0-agentic-loop/) and your job queue.

## Subscribe Like Any Rails Event

1.16 introduced instrumentation with five events. 2.0 has twenty: every model operation (chat, embeddings, images, video, speech, transcription, moderation, OCR, reranking, tokenization, batches, research jobs, compaction), plus per-attempt usage, plus the workflow and step wrappers themselves.

In Rails they go through `ActiveSupport::Notifications`, so you subscribe the way you'd subscribe to `sql.active_record`:

```ruby
# config/initializers/ruby_llm_instrumentation.rb
ActiveSupport::Notifications.subscribe("chat.ruby_llm") do |event|
  payload = event.payload

  Rails.logger.info(
    workflow: payload[:workflow_name],
    step: payload[:workflow_step_name],
    model: payload[:model],
    input_tokens: payload[:tokens].input,
    output_tokens: payload[:tokens].output,
    cost: payload[:cost].total,
    duration_ms: event.duration
  )
end
```

If you wrote subscribers for 1.16: tokens moved under `payload[:tokens]`, like everywhere else in 2.0. `payload[:input_tokens]` is gone.

For cost per article, subscribe to `usage.ruby_llm`. It fires once for every finished provider attempt, including the retries and cancelled streams that never produced a message, with `status`, `tokens`, and `cost`. Group by `workflow_id` and you have the cost of a piece of work, failed attempts included.

Outside Rails, set `config.instrumenter` to anything that responds to `instrument(name, payload)` and yields to the block. Add `activesupport` and use `ActiveSupport::Notifications` directly, or adapt the events to whatever your app already ships logs and metrics to.

## Attach Your Own Context

One-shot operations take `metadata:`. It lands in `payload[:metadata]` and is never sent to the provider:

```ruby
RubyLLM.embed(
  "A short document",
  metadata: { account_id: account.id, feature: "search" }
)
```

Workflows take it too, for data that belongs to the whole job:

```ruby
RubyLLM.workflow("Write article", id: "article-42", metadata: { account_id: account.id }) do |workflow|
  workflow.step("Draft") { WriterAgent.new.ask(notes).content }
end
```

Nested events get it as `workflow_metadata`, a separate key, so it never collides with per-call metadata.

## Nested Workflows and Steps

Steps nest, and each nested step carries `workflow_step_parent_id`. Workflows nest too: a service object that opens its own `RubyLLM.workflow` keeps its own identity and records `workflow_parent_id` (and `workflow_parent_step_id` when it was called from inside a step). The `workflow.ruby_llm` and `workflow_step.ruby_llm` events wrap each block, so your instrumenter gets timings and exceptions for them like any other event.

With these IDs, a subscriber can rebuild the execution tree of a run: the workflow, its steps, the model calls inside them, and what they cost.

Context follows RubyLLM's own concurrent tool execution. When you run work concurrently yourself, open the step inside each task:

```ruby
RubyLLM.workflow("Review code") do |workflow|
  Async do |task|
    security = task.async { workflow.step("Security") { SecurityAgent.new.ask(code) } }
    style = task.async { workflow.step("Style") { StyleAgent.new.ask(code) } }

    [security.wait, style.wait]
  end.wait
end
```

Context lasts exactly as long as the block, so it doesn't follow your work into a background job that runs tomorrow. Save the ID and re-enter:

```ruby
RubyLLM.workflow("Nightly summaries", id: run.workflow_id) do |workflow|
  workflow.step("Collect results") do
    batch = RubyLLM::Batch.find(run.batch_id, provider: :anthropic)
    batch.messages if batch.refresh.complete?
  end
end
```

`run` is your own record that holds the batch and workflow IDs. Because the ID is the same, events from both runs belong to the same workflow.

## Where This Goes

The API is `RubyLLM.workflow` and `workflow.step`. You wrap code you already have, and your events record which task each request belonged to.

In 2.1, configure your OpenTelemetry SDK, call `RubyLLM::OpenTelemetry.enable`, and those workflows and steps become spans, so the tree shows up in your tracing tool without writing a subscriber.

The [instrumentation guide](https://rubyllm.com/instrumentation/) lists every event and payload field. One note before you pipe everything into a log aggregator: payloads include message content, tool arguments, and provider responses, so export those only where your policy allows it.
