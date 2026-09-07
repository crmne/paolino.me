---
layout: post
title: "RubyLLM 2.0: The Agentic Loop, Exposed"
date: 2026-08-28
description: "RubyLLM 2.0 breaks ask into verbs you can drive yourself: stage a message, call the model once, run tools, step, resume mid-round, and cancel from anywhere."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
sendfox_campaign_id: 3009612
---
Strip any agent framework down and you find the same loop: call the model, run the tools it asked for, call the model again, stop when it answers without wanting a tool. RubyLLM has run that loop inside `ask` since 1.0. In 2.0, you can also control each step.

```ruby
# Run the agentic loop automatically
response = RubyLLM.chat(model: "claude-sonnet-4-6")
  .with_tools(Weather)
  .ask("What's the weather in Paris?")
# => #<RubyLLM::Message role: :assistant, content: "Here's the current...
```

```ruby
# Run the agentic loop manually
chat = RubyLLM.chat(model: "claude-sonnet-4-6")
  .with_tools(Weather)
  .ask_later("What's the weather in Paris?")

chat.step until chat.complete? || chat.awaiting_approval?  # generate, run_tools, generate
chat.messages.last.content
# => "Here's the current weather in **Paris, France**:\n\n- 🌡️ **Tempera...
```

`ask` still runs the loop for you, stopping when the answer is ready or a tool needs human approval. You can also call each part yourself:

* `ask_later` stages your message without sending anything.
* `generate` makes one model call and appends the response.
* `run_tools` executes pending tool calls and appends their results without calling the model.
* `step` runs pending tools if any are unanswered, otherwise it calls the model.
* `complete?` tells you when the conversation is settled: the model answered without calling a tool.
* `complete` steps until done or awaiting approval. `ask` is `ask_later` followed by `complete`.

This lets you set an iteration budget, batch the next generation, wait for approval, or save progress and continue in another job. Your code can check what happened between calls.

## One Step Per Job

Each verb decides what to do next by reading the persisted messages. That means the loop doesn't need to live in one process, or one machine, or one deploy:

```ruby
class AgentTurnJob < ApplicationJob
  def perform(chat_id)
    chat = Chat.find(chat_id).with_tools(Weather)
    chat.step
    AgentTurnJob.perform_later(chat_id) unless chat.complete? || chat.awaiting_approval?
  end
end
```

Each step gets its own job and retry boundary. A long sequence can release the worker between steps; an individual provider request or tool still takes as long as it takes.

The loop is resumable mid-tool-round too. `run_tools` skips calls whose results have been saved. If a process dies after saving one result out of three, reloading the chat and calling `step` executes only the remaining two. If it dies after an external action succeeds but before saving its result, the tool can run again. Use `tool_call.id` as an idempotency key for writes. On Rails 8.1 and later, you can use ActiveJob Continuations to build on this: checkpoint after each move and an agent run survives a redeploy, resuming from the persisted messages with no cursor to manage.

Batches are the same idea at scale: a batch is `generate` deferred for many chats at once, with `run_tools` run locally between rounds.

## Cancelable generation

`chat.cancel` cancels a run from another thread. At the next checkpoint, before a model call, before a tool executes, or between streamed chunks, the run raises `RubyLLM::CancelledError` and clears the flag so the chat can be reused.

In Rails, `acts_as_chat` stores the cancellation request on the chat record, so the signal travels through the database. A stop button in your web process halts a background job mid-stream:

```ruby
class ChatsController < ApplicationController
  def cancel
    current_user.chats.find(params[:id]).cancel
    head :no_content
  end
end
```

The job checks the chat record at cancellation checkpoints. It cannot interrupt arbitrary Ruby code inside a running tool; the next checkpoint observes the request.

## Halt Is Gone

RubyLLM 1.x let a tool terminate the loop from the inside: return `halt("done")` and the conversation ended. That put control flow inside a return value, and it's gone in 2.0, along with `RubyLLM::Tool::Halt`. Tools return results. Stopping belongs to the caller:

```ruby
until chat.complete? || chat.awaiting_approval?
  chat.step
  break if handed_off? # application-specific stopping condition
end
```

If what you want is one tool call per model response rather than a condition, `chat.with_tool_options(calls: :one)` does that. For a total round budget, count `step` or `generate` calls in the loop you control.

The full guide, including the workflow patterns built on these verbs, is at https://rubyllm.com/next/agentic-workflows/.
