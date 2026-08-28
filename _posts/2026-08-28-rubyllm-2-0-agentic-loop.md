---
layout: post
title: "RubyLLM 2.0: The Agentic Loop, Exposed"
date: 2026-08-28
description: "RubyLLM 2.0 breaks ask into verbs you can drive yourself: stage a message, call the model once, run tools, step, resume mid-round, and cancel from anywhere."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
sendfox_campaign_id: 3009612
---
Strip any agent framework down and you find the same loop: call the model, run the tools it asked for, call the model again, stop when it answers without wanting a tool. In RubyLLM 1.x that loop lived inside `ask`, sealed. In RubyLLM 2.0, you can also make it yours.

```ruby
# Run the agentic loop automatically
chat = RubyLLM.chat(model: "claude-sonnet-4-6")
  .with_tools(Weather)
  .ask("What's the weather in Paris?")
# => #<RubyLLM::Message role: :assistant, content: "Here's the current...
```

```ruby
# Run the agentic loop manually
chat = RubyLLM.chat(model: "claude-sonnet-4-6")
  .with_tools(Weather)
  .ask_later("What's the weather in Paris?")

chat.step until chat.complete?  # generate, run_tools, generate
chat.messages.last.content
=> "Here's the current weather in **Paris, France**:\n\n- 🌡️ **Tempera...
```

`ask` still works exactly as before: one method call runs the conversation to completion. But now it decomposes into verbs you can call yourself:

* `ask_later` stages your message without sending anything.
* `generate` makes one model call and appends the response. The model's move.
* `run_tools` executes the pending tool calls and appends their results. Your move. No model call.
* `step` does whichever move is next: tools if any are unanswered, otherwise a model call.
* `complete?` tells you when the conversation is settled: the model answered without calling a tool.
* `complete` steps until done. `ask` is `ask_later` followed by `complete`.

Why bother? Because sometimes you need finer control about what happens between or around steps. Iteration budgets. Batch generation. Human approval before a tool runs. Logging each move. Persisting the conversation and picking it up somewhere else. In 1.x you worked around a sealed loop. In 2.0 the loop is plain Ruby in your code if you want it.

## One Move Per Job

Each verb decides what to do next by reading the persisted messages. That means the loop doesn't need to live in one process, or one machine, or one deploy:

```ruby
class AgentTurnJob < ApplicationJob
  def perform(chat_id)
    chat = Chat.find(chat_id)
    chat.step
    AgentTurnJob.perform_later(chat_id) unless chat.complete?
  end
end
```

Every turn is its own job. Your queue gets granular retries, your agents survive restarts, and a long run never monopolizes a worker.

The loop is now resumable mid-tool-round too. `run_tools` skips tool calls that already have results, so if a process dies after finishing one tool call of three, reloading the chat and calling `step` executes only the remaining two. On Rails 8.1 and later, you can use ActiveJob Continuations to build on this: checkpoint after each move and an agent run survives a redeploy, resuming from the persisted messages with no cursor to manage.

Batches are the same idea at scale: a batch is `generate` deferred for many chats at once, with `run_tools` run locally between rounds.

## Cancelable generation

`chat.cancel!` cancels a run from another thread. At the next checkpoint, before a model call, before a tool executes, or between streamed chunks, the run raises `RubyLLM::CancelledError` and clears the flag so the chat can be reused.

In Rails, `acts_as_chat` stores the cancellation request on the chat record, so the signal travels through the database. A stop button in your web process halts a background job mid-stream:

```ruby
class ChatsController < ApplicationController
  def cancel
    Chat.find(params[:id]).cancel!
    head :no_content
  end
end
```

No pub/sub channel, no Redis flag, no process signals. The job checks the record it already has and stops.

## Halt Is Gone

RubyLLM 1.x let a tool terminate the loop from the inside: return `halt("done")` and the conversation ended. That put control flow inside a return value, and it's gone in 2.0, along with `RubyLLM::Tool::Halt`. Tools return results. Stopping belongs to the caller:

```ruby
until chat.complete?
  chat.step
  break if handed_off? # your halt, in your code
end
```

If what you want is one tool call per model response rather than a condition, `chat.with_tool_options(calls: :one)` does that. For a total round budget, count `step` or `generate` calls in the loop you control.

The full guide, including the workflow patterns built on these verbs, is at https://rubyllm.com/next/agentic-workflows/.
