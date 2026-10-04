---
layout: post
title: "RubyLLM 2.0: Tools That Wait for a Yes"
date: 2026-10-06
description: "Mark a tool requires_approval and RubyLLM 2.0 parks the call until a human decides, even across Rails jobs, restarts, and deploys."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---
I want my support agent to look up an order on its own. Refunding that order is a different conversation. Before money moves, I want to see the exact call, with the exact arguments, and say yes.

In RubyLLM 2.0 that's one line:

```ruby
class RefundOrder < RubyLLM::Tool
  description "Refunds a customer order"
  parameter :order_id, description: "ID of the order to refund"
  requires_approval

  def execute(order_id:, tool_call: nil)
    Refunds.issue(order_id:, idempotency_key: tool_call.id)
  end
end
```

Of everything in 2.0, this is the feature I'm happiest with. Not because it's big. Because it's small, and it's the thing standing between "a demo agent" and "an agent I'd let near a payment provider."

## Ask, Pause, Decide

```ruby
chat = RubyLLM.chat.with_tools(RefundOrder)
chat.ask "Refund order 42."

chat.awaiting_approval? # => true, and nothing has executed
call = chat.pending_approvals.first
call.name               # => "refund_order"
call.arguments          # => {"order_id" => "42"}

chat.approve(call)
chat.complete           # runs the refund, then the model answers
```

`ask` runs the loop until there's nothing left it's allowed to do, then returns. No thread sits there blocking on a human. The model asked for something, the chat recorded the request, and now it's your move.

Say no and the model hears about it:

```ruby
chat.deny(call)
chat.complete
```

The denied call never executes. The model gets a tool result that reads `The user denied the refund_order tool call.` and carries on from there. It can explain, offer something else, or ask what you'd prefer. No exception, no dead end.

Tools that don't need approval still run in the same round. If the model asks to look up the order and refund it, the lookup happens and the refund waits.

## Yes, No, or Not Yet

A decision has three values: `true`, `false`, and `nil`. Yes, no, still waiting.

`approve` and `deny` take a `ToolCall` or its ID. If your app already keeps approvals somewhere, point the tool at them with a resolver:

```ruby
class RefundOrder < RubyLLM::Tool
  requires_approval do |call|
    RefundApproval.find_by(tool_call_id: call.id)&.approved
  end
end
```

Return `true` to run, `false` to deny, `nil` to keep waiting. Once a tool has a resolver, the resolver is the source of truth. RubyLLM may call it several times while a call waits, including after a restart, so keep it a read.

One rule keeps the transcript honest: finish the round before you say anything new. `ask` and `ask_later` raise `RubyLLM::PendingToolCallsError` while a call is still unanswered. A tool call without a result is a transcript providers refuse, so RubyLLM refuses it first.

## The Part I Actually Wanted: It Survives Everything

Pausing in memory is the easy part. The interesting question is what happens when the human takes twenty minutes, goes to lunch, and you deploy twice in the meantime.

With `acts_as_chat`, the tool call and its decision are rows in your database. Nothing is waiting in memory. Define the agent so any process can restore the tools:

```ruby
class SupportAgent < RubyLLM::Agent
  chat_model Chat
  tools RefundOrder
end

class ChatJob < ApplicationJob
  def perform(chat_id)
    SupportAgent.find(chat_id).complete
  end
end
```

Load through `SupportAgent.find`, not `Chat.find`. A bare record has the transcript but no tools, so it doesn't know `RefundOrder` needs approval and has nothing to run once it's approved.

Your message controller stages the question with `ask_later` and enqueues `ChatJob`. The job runs until the model asks for a refund, saves the call, and finishes. The worker is free. Render `SupportAgent.find(chat_id).pending_approvals` as approval cards, with the name and arguments of each call.

When the user clicks:

```ruby
class ToolApprovalsController < ApplicationController
  def create
    chat = current_user.chats.find(params[:chat_id])
    approved = ActiveModel::Type::Boolean.new.cast(params[:approved])

    approved ? chat.approve(params[:tool_call_id]) : chat.deny(params[:tool_call_id])

    ChatJob.perform_later(chat.id)
    head :ok
  end
end
```

The next job, on whatever worker picks it up, reads the decision and continues. Same call, same ID, same arguments. The deploy never noticed.

That's the whole design: an approval is data, not a blocked thread. Workers finish their jobs. Users take their time. Nobody holds a connection open for a lunch break.

## Approved Twice Is Still Once

Approval survives restarts. So does everything else, including the awkward case: a process can die after the refund went through but before its result was saved. The next job sees an approved call with no result and runs it again.

That's why the tool passes `tool_call.id` to the payment provider as an idempotency key. The human approved one specific call, and the side effect should carry that same identity. For writes in your own database, a unique constraint on the call ID does the same job.

## Remote Tools Too

Approval isn't only for Ruby tools. When OpenAI or Azure runs a tool on a remote MCP server, the provider can pause before the call, and it lands in the same `pending_approvals` list. `call.remote?` tells you the provider will execute it. `approve`, `deny`, and `complete` work exactly the same, and RubyLLM sends your decision to the provider instead of running anything locally.

Thanks to [@jondavidschober](https://github.com/jondavidschober) for the issue that started this ([#503](https://github.com/crmne/ruby_llm/issues/503)).

The [tool execution guide](https://rubyllm.com/tool-execution/#requiring-approval) covers the full lifecycle, and [Durable Agents](https://rubyllm.com/durable-agents/) covers jobs, restarts, and cancellation. If you're driving the loop step by step, the [agentic loop post](/rubyllm-2-0-agentic-loop/) shows where approvals fit.
