---
layout: post
title: "Your Agent's Context Window Is Not a Junk Drawer"
date: 2026-03-17
description: "MCP is training wheels you should outgrow, A2A solves problems you don't have, and the only thing that matters is knowing what's in your context window."
tags: [AI, LLM, MCP, A2A, Agents, Developer Experience]
image: /images/context-rot.png
---

I keep getting feature requests for RubyLLM that follow the same shape. "Add MCP support." "Add A2A." "What about agent-to-agent communication?" I've thought about each of them for a while now, and I've come to a position that's worth writing down.

It starts with MCP.

## MCP: a useful crutch you should eventually throw away

Let me be clear: MCP is a fine idea. You need to talk to a service? Don't want to write the tool definition yourself? Grab an MCP server, plug it in, and you're running in ten minutes. For prototyping, for exploration, for the "let me see if this is even worth building" phase... it's great!

The problem is what happens next. Which is: nothing. People leave the MCP servers plugged in. They add more. They treat their agent's context window like a junk drawer. Just toss it in there, the LLM will figure it out.

It won't. Or rather, it will, but worse than you think.

Every MCP server you connect dumps tool descriptions, schemas, and instructions into your context. You didn't write those descriptions. You didn't optimize them. You probably haven't even read them. You're handing over a chunk of your strictly limited context window — the most precious resource your agent has — to whatever some third party decided to shove in there.

It's the equivalent of letting strangers put random items on your desk and then wondering why you can't find anything. In the LLM world, we call that [context rot](https://research.trychroma.com/context-rot): the more tokens you stuff into the window, the worse your model performs, regardless of how big the window is.

These aren't just performance problems. They're security problems too. Those tool descriptions are text that gets interpreted by an LLM. You're injecting untrusted content directly into the brain of your agent. Every MCP server is a prompt injection surface you didn't audit.

My take is simple: use MCP to prototype. Then replace it with purpose-built tools you actually control. Write the tool descriptions yourself. Keep your context tight. Know exactly what's in there and why.

## A2A: convention over protocol

And then there's A2A, Google's Agent-to-Agent protocol. Agent Cards for capability discovery, task lifecycle state machines, modality negotiation, SDKs in five languages, a Linux Foundation project. The whole enterprise enchilada.

The pitch is that agents should collaborate "as agents, not just as tools."

That last bit is the tell. Read it again. "Not just as tools."

The claim is that tool calling isn't enough. That agents need persistent conversations, shared state, ongoing collaboration... the things that make an agent an *agent* rather than a function.

Bullshit. Let me show you.

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

First call, `chat_id` is nil, a new researcher is spawned. The tool returns the result *and* the `chat_id`. Next time the assistant needs to follow up, it passes the `chat_id` back, and the researcher picks up where it left off. Full conversation history persisted. Agents decide which context to pass each other. 22 lines of [RubyLLM](https://rubyllm.com) code.

That's persistent conversation, shared state, ongoing collaboration, and capability discovery. With an optional parameter on a tool.

We don't need a protocol for agents to talk to each other. We need a convention. This ties back to the same context window problem: every protocol comes with metadata, capability schemas, and negotiation overhead that ends up as tokens in your window. A2A doesn't just add complexity to your architecture. It adds complexity to your context.

## The pattern

There's a pattern in the AI world right now that feels familiar if you've been around tech long enough.

I've watched this happen with Big Data, with microservices, with Kubernetes. Every time, a real need gets wrapped in so much ceremony that people forget the problem was simple to begin with. Most apps that "needed" Hadoop could have used a SQL database. Most companies that "needed" microservices needed a well-organized monolith. Most deployments that "needed" Kubernetes needed a single server and a deploy script.

A2A is the same pattern applied to agents. The real problem (agents need to call other agents) is an optional parameter on a tool.

But the companies pushing the ceremony aren't doing it because they know better. They're doing it because being the standard is the business model.

Build what you need. Know what's in your context. Shut the noise.
