---
layout: post
title: "RubyLLM 2.0: Own the Transcript"
date: 2026-11-02
description: "Rewrite the history the model sees, compact long conversations, inspect the exact request, and read why the model stopped in RubyLLM 2.0."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
image: /images/rubyllm-2.0-transcript.png
---
A long conversation is full of things the user wants to keep and the model no longer needs to reread on every request. In RubyLLM 2.0 you can rewrite the history you send:

```ruby
chat.messages = messages_for_model
```

The setter takes `Message` objects, attribute hashes, or records that respond to `to_llm`. You can summarize old turns, redact values, or drop a tangent, and the next request sends exactly what you put there.

RubyLLM doesn't decide what's important for you. Your app knows that better than a generic memory framework would.

## Summarize the Old Stuff

For a text conversation, keep the instructions and the last few turns, and fold the rest into a summary:

```ruby
history = chat.messages
instructions, turns = history.partition { |message| message.role == :system }

if turns.length > 4
  earlier = turns[0...-4].map { |message| "#{message.role}: #{message.content}" }.join("\n\n")

  summary = RubyLLM.chat(model: "gpt-5.6-luna")
    .ask("Summarize the decisions and open questions:\n\n#{earlier}")

  chat.messages = [
    *instructions,
    { role: :user, content: "Earlier in this conversation: #{summary.content}" },
    *turns.last(4)
  ]
end
```

That works because `message.content` is now a String or `nil`, nothing else. Structured output is JSON text with a `parsed` reader, and files live on `message.attachments`. You no longer unwrap `RubyLLM::Content` to edit text.

Conversations with tools need more care. Every tool call needs its result, and reasoning or provider-tool blocks the protocol replays have to stay with their message. Slice the last four messages blindly and you can cut a call from its result, which providers reject.

## Two Transcripts in Rails

On a Rails record, `messages=` is Active Record's association writer, which is a different method. For a temporary model-facing rewrite, go through the RubyLLM chat:

```ruby
chat_record.to_llm.messages = messages_for_model
```

That changes what the next request sends. New messages still persist through the normal callbacks, and reloading the record brings the stored history back.

When the difference is permanent, say, the user sees everything but the model sees a redacted, compacted version, give RubyLLM its own association:

```ruby
class Conversation < ApplicationRecord
  has_many :messages

  acts_as_chat messages: :llm_messages,
               message_class: "LlmMessage"
end
```

Your UI renders `messages` with whatever retention and moderation rules you like. RubyLLM persists and sends `llm_messages`.

## Let the Provider Compact

Some providers can shrink a long conversation themselves when it crosses a threshold:

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5")
  .with_compaction(at: 100_000, instructions: "Keep every decision and every number.")
```

`at:` is the input-token trigger, `instructions:` steers the summary, and `pause_after:` ends the turn right after compaction instead of continuing into the answer. A bare `with_compaction` uses the provider's defaults, and `with_compaction(false)` turns it off. Agents declare it with `compaction at: 100_000`.

Anthropic and OpenAI Responses write an opaque compacted block, which RubyLLM keeps and replays on later requests. OpenRouter does something different: it drops messages from the middle once the context is full, with no threshold and no summary.

You can also compact on demand:

```ruby
chat = RubyLLM.chat(model: "gpt-5.6")
chat.ask "The project codename is Thimble. We write it in Ruby."

chat.compact
chat.ask "What is the project codename?"
```

`compact` calls the provider's compaction endpoint (OpenAI, Azure, and xAI Responses) and returns a message carrying the compacted context. Later requests use it, while `chat.messages` keeps every original message. In Rails, the compacted context persists too, so a job that loads the chat tomorrow continues from it.

Either way, the provider's summarization is billed work, and RubyLLM counts its reported usage alongside the answers.

## Look at the Request Before You Send It

When the provider has a field RubyLLM doesn't name, `with_provider_options` merges it in. When you need to see or rearrange the final payload, there's `before_request`, and `render` shows you the result without calling the model:

```ruby
chat = RubyLLM.chat(model: "gpt-5.6")
  .ask_later("Summarize the changes.")

chat.before_request do |payload|
  payload[:metadata] = { review_id: "review-42" }
end

chat.render[:metadata] # => { review_id: "review-42" }
chat.complete
```

The hook runs after all of RubyLLM's formatting and provider-option merging, and mutates the payload in place. It speaks the selected protocol's wire format, so a hook written for OpenAI needs revisiting if you move to Anthropic. Nothing it adds is saved as message content.

`render` also lets you test request shaping: assert on the payload without network access or an API key. (In 2.1, responses stop carrying a copy of the request they answered, to save memory, so `render` and `before_request` are how you see what was sent.)

For a fixed field like this one, `with_provider_options(metadata: { review_id: "review-42" })` is simpler. This metadata goes to the provider. Metadata for your own observability belongs on a [workflow](https://rubyllm.com/instrumentation/) instead.

## Why Did It Stop?

Finish reasons are now normalized symbols:

```ruby
response = chat.complete

response.finish_reason    # => :stop, :max_tokens, :tool_calls, or :content_filter
response.stopped?
response.max_tokens?
response.tool_call_stop?
response.content_filtered?
```

A truncated answer is `:max_tokens` whether the provider said `length`, `max_tokens`, or `MAX_TOKENS`. Anthropic's `end_turn`, Gemini's `STOP`, and the Responses API's `completed` are all `:stop`. Reasons RubyLLM doesn't map, like Anthropic's `pause_turn`, come through as symbols in the provider's spelling. A failed request raises instead of returning a reason. Persisted messages have the same predicates when the table has a `finish_reason` column.

Checking for a cut-off answer works the same way on every provider. `:max_tokens` covers the output cap and, on Anthropic, a full context window, so look at `with_max_output_tokens` first and the transcript second.

Thanks to [@mnort9](https://github.com/mnort9) and [@marksweston](https://github.com/marksweston) for pushing on transcript control, [@fvaleye](https://github.com/fvaleye) for compaction, and [@trevorturk](https://github.com/trevorturk) and [@losingle](https://github.com/losingle) for finish reasons.

The details live in the [request control guide](https://rubyllm.com/chat-request-control/) and the [persistence guide](https://rubyllm.com/rails-persistence/#separate-user-and-llm-transcripts).
