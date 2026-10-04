---
layout: post
title: "RubyLLM 2.0: Workflows Without a Workflow Engine"
date: 2026-11-09
description: "RubyLLM.workflow names a task and its steps so every model call, tool call, and usage event can be traced back to it. Your control flow stays Ruby."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM, Observability]
---

A research agent calls a model, searches the web a few times, and hands its notes to a writing agent. The Ruby is four lines. The logs are forty unrelated events, and good luck figuring out which ones wrote article 42.

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

Every RubyLLM event inside that block now carries `workflow_id` and `workflow_name`. Inside a step, it also carries `workflow_step_id` and `workflow_step_name`. Model calls, tool calls, usage rows for retries, all of it, tagged and groupable.

The blocks return their normal values. `notes` is a String. Nothing else about your code changed.

## Why Not a Workflow Engine

Every AI framework eventually grows a graph DSL: nodes, edges, a state object, a runtime that executes it all for you. I looked at that and asked what it buys a Ruby developer.

A sequence is already method calls. A branch is a `case`. A loop is a loop. A retry is `retry`. What you actually lack is not a way to express control flow; it's a way to see it afterwards. So that's all `RubyLLM.workflow` does.

`workflow.step` runs your block and adds context to the events inside it. It doesn't persist progress, schedule anything, or retry. Branches, loops, error handling, and concurrency stay in your code, where you can read them. Want durability? That's what [the agentic loop's verbs](/rubyllm-2-0-agentic-loop/) and your job queue are for.

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

Want cost per article? Subscribe to `usage.ruby_llm`. It fires once for every finished provider attempt, including the retries and cancelled streams that never produced a message, with `status`, `tokens`, and `cost`. Group by `workflow_id` and you have the real cost of a piece of work, not just the cost of the attempts that succeeded.

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

## Trees, Not Just Tags

Steps nest, and each nested step carries `workflow_step_parent_id`. Workflows nest too: a service object that opens its own `RubyLLM.workflow` keeps its own identity and records `workflow_parent_id` (and `workflow_parent_step_id` when it was called from inside a step). The `workflow.ruby_llm` and `workflow_step.ruby_llm` events wrap each block, so your instrumenter gets timings and exceptions for them like any other event.

Put that together and a subscriber can rebuild the execution tree of a run: this workflow, these steps, these model calls inside them, this much money.

Context follows RubyLLM's own concurrent tool execution. Your own concurrency is your call, so open the step inside each task:

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

`run` is your own record that holds the batch and workflow IDs. Same ID, same workflow, two days apart.

## Where This Goes

That's the whole API: one method, one block, one `step`. I like features that cost this little to adopt. You wrap code you already have, and your logs start telling you which task each request belonged to.

In 2.1, configure your OpenTelemetry SDK, call `RubyLLM::OpenTelemetry.enable`, and those workflows and steps become spans, so the tree shows up in your tracing tool without a subscriber in sight.

The [instrumentation guide](https://rubyllm.com/instrumentation/) lists every event and payload field. One note before you pipe everything into a log aggregator: payloads include message content, tool arguments, and provider responses, so export those only where your policy allows it.
