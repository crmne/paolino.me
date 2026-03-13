---
layout: post
title: "Your Agent's Context Window Is Not a Junk Drawer"
date: 2026-03-17
description: "MCP is training wheels you should outgrow, A2A solves problems you don't have, and the only thing that matters is knowing what's in your context window."
tags: [AI, LLM, MCP, A2A, Agents, Developer Experience]
---

There's a pattern emerging in the LLM tooling world that I find genuinely concerning. Not the fun kind of concerning where a new framework threatens your market share. The boring insidious kind, where an entire ecosystem is building habits that will make everyone's AI applications worse.

It starts with MCP.

## MCP: a useful crutch you should throw away

Let me be clear: MCP is a fine idea. You need to talk to a Postgres database? Don't want to write the tool definition yourself? Grab an MCP server, plug it in, you're running in ten minutes. For prototyping, for exploration, for the "let me see if this is even worth building" phase... it's great!

The problem is what happens next. Which is: nothing. People leave the MCP servers plugged in. They add more. They treat their agent's context window like a junk drawer. Just toss it in there, the LLM will figure it out.

It won't. Or rather, it will, but worse than you think.

Every MCP server you connect dumps tool descriptions, schemas, and instructions into your context. You didn't write those descriptions. You didn't optimize them. You probably haven't even read them. You're handing over a chunk of your strictly limited context window, the most precious resource your agent has, to whatever some third party decided to shove in there.

This is the equivalent of letting strangers put random items on your desk and then wondering why you can't find anything.

And it's not just a performance problem. It's a security problem. Those tool descriptions are text that gets interpreted by an LLM. You're injecting untrusted content directly into the brain of your agent. Every MCP server is a prompt injection surface you didn't audit.

My stance on this is simple: use MCP to prototype. Then replace it with purpose-built tools you actually control. Write the tool descriptions yourself. Keep your context tight. Know exactly what's in there and why.

## A2A: convention over protocol

And then there's A2A, Google's Agent-to-Agent protocol. Agent Cards for capability discovery, task lifecycle state machines, modality negotiation, SDKs in five languages, a Linux Foundation project — the whole enterprise enchilada. The pitch is that agents should collaborate "as agents, not just as tools."

That last bit is the tell. Read it again. "Not just as tools."

Okay. So the claim is that tool calling isn't enough. That agents need persistent conversations, shared state, ongoing collaboration... the things that make an agent a *serious agent* rather than a mere function. Let me show you how you can replicate that in practice:

```ruby
class Researcher < RubyLLM::Agent
  chat_model Chat
  instructions "You are an expert researcher. Be concise and factual."
end
```

```ruby
class ResearchTool < RubyLLM::Tool
  description "Delegates research questions to a specialist researcher. Returns a chat_id to continue the conversation with the same researcher."

  param :query, desc: "The research question"
  param :chat_id, desc: "Chat ID to continue a previous research conversation", required: false

  def execute(query:, chat_id: nil)
    researcher = chat_id ? Researcher.find(chat_id) : Researcher.create!
    response = researcher.ask(query)
    { result: response.content, chat_id: researcher.id }
  rescue => e
    { error: e.message }
  end
end
```

```ruby
class Assistant < RubyLLM::Agent
  instructions "Use the research tool for factual questions. Pass the chat_id to follow up with the same researcher."
  tools ResearchTool
end
```

That's it. First call, `chat_id` is nil, a new researcher is spawned. The tool returns the result *and* the chat ID. Next time the assistant needs to follow up, it passes the chat ID back, and the researcher picks up where it left off. Full conversation history, full context. Two agents, maintaining an ongoing collaboration, with shared state persisted in the database. 22 lines of code.

That is what A2A calls agent-to-agent communication. It's an optional parameter on a tool.

We don't need a *protocol* for agents to talk to each other. We need a *convention*. And this ties back to the same context window problem: every protocol comes with metadata, descriptions, capability schemas, and negotiation overhead that ends up as tokens in your window. A2A doesn't just add complexity to your architecture. It adds complexity to your context.

## Keep it tight

Both MCP overuse and A2A enthusiasm come from the same impulse: the belief that the latest trendy abstraction layer cake is always better. That if you just add another protocol, another layer, another standard, the hard problems will somehow get easier.

They won't. They'll just get more abstract.

Know what's in your context window. Write your own tools.

Everything else is ceremony.
