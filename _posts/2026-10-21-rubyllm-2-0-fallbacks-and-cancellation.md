---
layout: post
title: "RubyLLM 2.0: Fallbacks, Cancellation, and Errors"
date: 2026-10-21
description: "Fall back to another model when a provider fails, stop a Rails background stream from a button, and keep error policy on the agent in RubyLLM 2.0."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---
Providers go down, and switching the model and redeploying is a slow way to respond. In RubyLLM 2.0 you declare backup models on the chat:

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5")
  .with_fallbacks("gpt-5.6", "gemini-3.7-flash")

response = chat.ask "Summarize this incident report."
```

If Claude fails with a rate limit, a server error, an overload, a timeout, or a dropped connection, RubyLLM retries the same request on GPT, then Gemini, with the same conversation, tools, schema, and settings. Once that generation is done, the chat goes back to Claude.

## Which Failures Fall Back

The defaults are the transient ones: `RateLimitError`, `ServerError`, `ServiceUnavailableError`, `OverloadedError`, plus Faraday timeouts and connection failures. Authentication and bad-request errors don't fall back, because a wrong API key on provider A is not a reason to quietly bill provider B.

`on:` replaces the list. The defaults are a public constant, so extending them is easy. Here a cheap model with a 200K window hands long conversations to one with a million:

```ruby
chat = RubyLLM.chat(model: "claude-haiku-4-5").with_fallbacks(
  "gemini-3.7-flash",
  on: [*RubyLLM::Fallback::DEFAULT_ERRORS, RubyLLM::ContextLengthExceededError]
)
```

Agents declare the same thing, so every chat they build or load gets it:

```ruby
class SupportAgent < RubyLLM::Agent
  model "claude-sonnet-5"
  fallbacks "gpt-5.6", "gemini-3.7-flash"
end
```

Fallbacks need credentials for each provider, and each fallback has to support what you're asking for. A structured-output request won't fall back gracefully onto a model that can't do structured output.

## Know When It Happened

```ruby
chat.before_fallback do |fallback|
  Rails.logger.info(
    "Falling back from #{fallback.from.id} to #{fallback.to.id}: #{fallback.error.class}"
  )
end

chat.after_fallback do |fallback|
  if fallback.succeeded?
    Rails.logger.info("#{fallback.to.id} saved the day (attempt #{fallback.attempt})")
  else
    Rails.logger.warn("#{fallback.to.id} failed too: #{fallback.fallback_error.class}")
  end
end
```

The trickiest case is streaming. The first model may have streamed half a sentence to the user before it died. RubyLLM can't take those chunks back, so the fallback starts a fresh assistant message, and `fallback.chunks_yielded?` tells you the user already saw something. Clear or mark the partial answer in your UI, or Gemini's answer will be appended to the middle of Claude's sentence.

Failed attempts also cost money. Every attempt lands in the usage ledger, so `chat.cost` includes the half-answer you threw away.

## Stopping a Stream from Another Process

The basics of `chat.cancel` are in the [agentic loop post](/rubyllm-2-0-agentic-loop/): call it from anywhere, and the run raises `RubyLLM::CancelledError` at its next checkpoint. The harder case is the stop button in a Rails app, where the stream runs in a job and the button lives in a different process.

```ruby
class ChatsController < ApplicationController
  def cancel
    current_user.chats.find(params[:id]).cancel
    head :no_content
  end
end

class ChatStreamJob < ApplicationJob
  def perform(chat_id)
    chat = SupportAgent.find(chat_id)
    chat.complete do |chunk|
      chat.messages.last&.broadcast_append_chunk(chunk.content) if chunk.content
    end
  rescue RubyLLM::CancelledError
    # broadcast a "stopped" state if your UI shows one
  end
end
```

`acts_as_chat` writes the request to the chat's `cancelled` column. The streaming job checks that column between chunks, at most once a second and outside the query cache, so it sees a write from another process without hammering your database. When it sees it, it clears the flag, raises, and cleans up after itself: the empty assistant row the stream created is removed, so the transcript doesn't end in an empty message. The tokens the provider already produced still go into the usage ledger as a cancelled attempt.

The stop button and the job only share the chat record you already have, so you don't need a Redis key, a pub/sub channel, or a separate cancellation service.

It's cooperative. A tool in the middle of arbitrary Ruby code finishes before the next checkpoint notices, and closing a browser tab doesn't call `cancel` for you, so wire your stop button to it.

## Rescue by Class

Provider errors come with useful subclasses:

```ruby
begin
  chat.ask "Generate the quarterly summary."
rescue RubyLLM::RateLimitError
  retry_later
rescue RubyLLM::PaymentRequiredError
  notify_billing
rescue RubyLLM::Error => error
  Rails.logger.error("#{error.class}: #{error.response&.status}")
end
```

`RubyLLM::Error` covers anything that went wrong talking to a provider, and `error.response` keeps the HTTP response when there was one. Mistakes on your side, like `ConfigurationError`, `ModelNotFoundError`, or `PendingToolCallsError`, inherit straight from `StandardError`, and so does `CancelledError`, so `rescue RubyLLM::Error` won't treat a user pressing stop as a provider failure.

## Error Policy Belongs on the Agent

Rescue blocks around every call site get copied and drift apart. Agents declare their policy once with `rescue_from`, the way Rails controllers do:

```ruby
class ApplicationAgent < RubyLLM::Agent
  rescue_from RubyLLM::RateLimitError, RubyLLM::ServerError, with: :instrument_and_raise

  private

  def instrument_and_raise(error)
    StatsD.increment("llm.api_error", tags: ["type:#{error.class.name.demodulize}"])
    raise
  end
end

class SupportAgent < ApplicationAgent
  rescue_from RubyLLM::CancelledError do
    nil # the user stopped it; nothing to report
  end
end
```

Handlers cover `ask`, `say`, `ask_later`, `complete`, `generate`, `run_tools`, `step`, `count_tokens`, and `compact`. They run on the agent instance, so inputs and `chat` are right there. The semantics are `ActiveSupport::Rescuable`'s: last matching declaration wins, subclasses can override, `raise` passes the error to the caller, and otherwise the handler's return value becomes the call's return value.

One thing to know: handlers wrap agent instances. `SupportAgent.new.ask` goes through them. `SupportAgent.find` and `SupportAgent.chat` hand you the configured record or chat itself, which doesn't. To get the handlers on a persisted chat, wrap it: `SupportAgent.new(chat: Chat.find(id), persist_instructions: false)`. In jobs, retry policy often reads better in Active Job anyway.

Thanks to [@kieranklaassen](https://github.com/kieranklaassen) for asking for fallbacks ([#621](https://github.com/crmne/ruby_llm/issues/621)), [@sh1nj1](https://github.com/sh1nj1) for cancellable streams ([#607](https://github.com/crmne/ruby_llm/issues/607)), and [@skovy](https://github.com/skovy) for `rescue_from` ([#708](https://github.com/crmne/ruby_llm/issues/708)).

The [error handling guide](https://rubyllm.com/error-handling/) covers fallbacks and the error hierarchy, [Rails streaming](https://rubyllm.com/rails-streaming/#cancelling-a-background-stream) covers the stop button, and the [agents guide](https://rubyllm.com/agents/#handling-errors-with-rescue_from) covers handlers.
