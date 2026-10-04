---
layout: post
title: "RubyLLM 2.1: OpenTelemetry Tracing, Without Your Prompts"
date: 2026-10-12
description: "RubyLLM 2.1 traces model calls, tools, and workflows with OpenTelemetry in one line, and exports metadata only, never prompts or responses."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM, OpenTelemetry, Observability]
---
```ruby
RubyLLM::OpenTelemetry.enable
```

That's the feature. RubyLLM 2.1 is out today, and with that line every model call, tool run, and workflow shows up as a span in the tracing backend you already use: Jaeger, Honeycomb, Grafana Tempo, Datadog, anything that takes OTLP.

## What You See

Wrap related work in a workflow and it becomes one trace:

```ruby
RubyLLM.workflow("Answer question") do |workflow|
  workflow.step("Generate answer") do
    SupportAgent.new.ask("Where is order 42?")
  end
end
```

```text
invoke_workflow Answer question
└── ruby_llm.workflow_step Generate answer
    ├── chat gpt-5.6-luna
    ├── execute_tool lookup_order
    │   └── GET /orders/42          (from your HTTP instrumentation)
    └── chat gpt-5.6-luna
```

The agent asks the model, runs the tool the model chose, asks again with the result. RubyLLM's spans join the current OpenTelemetry context, so the HTTP call your tool makes nests under the tool that made it, and a chat inside a Rails request joins that request's trace. When an agent is slow, you see whether it was the model, the tool, or the third round trip nobody expected.

The rest is covered too: embeddings, images, speech, transcription, OCR, reranking, moderation, and judgments each get their own span. Retries stay inside one model call's span. Each fallback model gets its own. A streaming span stays open until the last chunk. Concurrent tools, on threads or fibers, carry the trace context with them, so they land in the right trace instead of floating off on their own.

## Built on What Was Already There

This didn't need a rewrite, because the foundation was already in place.

RubyLLM 1.16 added [structured instrumentation events](/rubyllm-1-16/#instrumentation-without-monkey-patching) for everything the library does, specifically so nobody would have to monkey patch it to see inside. RubyLLM 2.0 added [`RubyLLM.workflow`](https://rubyllm.com/instrumentation/#workflows-and-steps) to group calls into named steps. OpenTelemetry tracing is a subscriber to those same events. Your `config.instrumenter`, your Rails notification subscribers, and anything else listening keep receiving exactly what they did before.

## Your SDK, Your Exporters

RubyLLM never configures, starts, flushes, or shuts down your OpenTelemetry SDK. It asks the tracer provider your application set up for a tracer, and that's all. If you haven't set one up yet:

```ruby
# Gemfile
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
```

```ruby
# config/initializers/opentelemetry.rb
require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"

OpenTelemetry::SDK.configure do |config|
  config.service_name = "my-app"
end

RubyLLM::OpenTelemetry.enable
```

RubyLLM doesn't add an OpenTelemetry dependency to your app. `enable` loads `opentelemetry-api` (which the SDK brings along) only when you call it. It covers the whole process, including chats that already exist and isolated contexts, and calling it twice is harmless. `RubyLLM::OpenTelemetry.disable` stops tracing new operations and lets running spans finish.

And if tracing itself fails, RubyLLM logs a warning and your call carries on. Observability that takes down the thing it observes is a hobby, not a feature.

## Metadata, Never Content

Here's the part I care about most.

Spans follow the [OpenTelemetry GenAI semantic conventions](https://github.com/open-telemetry/semantic-conventions-genai/tree/main/docs/gen-ai): provider, requested and actual model, temperature and max tokens when set, finish reasons, input and output tokens, cached and reasoning tokens, tool names and call IDs, workflow and step names. Enough to know where the time and the tokens went.

What RubyLLM will never put in a span: prompts, instructions, messages, generated content, embeddings, tool arguments or results, the metadata you attach to calls, provider options, credentials, or exception messages. When something raises, the span gets the error status and the exception class. Not the message, because exception messages love to quote the input that caused them.

This is deliberate, and there's no flag to turn it on. Traces usually go to a third party. Your users typed things into your app because they trust your app, not your tracing vendor. Most of what you need from a trace is shape and timing: which call was slow, which tool ran twice, where the tokens went. You don't need the customer's medical question in Honeycomb to find out that the second model call took nine seconds.

If you do need content for debugging, you already have it. The instrumentation events your own subscribers receive still carry the full payloads, and what you do with them is your decision, made in your code, under your data policy. It's not a default buried in a library.

The one thing to watch: model names, tool names, and workflow names and IDs are exported. Name your workflows `"Answer question"`, not `"Answer question for jane@example.com"`.

## Read More

The [OpenTelemetry guide](https://rubyllm.com/opentelemetry/) has the full span and attribute reference, plus how to carry context into jobs you start yourself. Evaluations in 2.1 run every trial as a workflow, so each one shows up as its own trace; the [evaluation progress guide](https://rubyllm.com/evaluation-progress/#tracing) shows what that looks like.

```ruby
gem 'ruby_llm', '~> 2.1.0'
```

One line, and your agents stop being a black box. Your users' words stay where they were.
