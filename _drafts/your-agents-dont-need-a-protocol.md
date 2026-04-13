---
layout: post
title: "Your Agents Don't Need a Protocol"
description: "A2A solves problems you don't have. Twenty lines of code already solved them."
tags: [AI, LLM, A2A, Agents, Developer Experience]
sendfox_campaign_id: 2772799
---
A2A is Google's Agent-to-Agent protocol. Agent Cards for capability discovery, task lifecycle state machines, modality negotiation, SDKs in five languages, a Linux Foundation project. The whole enterprise enchilada.

The pitch is that agents should collaborate "as agents, not just as tools."

That last bit is the tell. Read it again. "Not just as tools."

Someone opened an issue on RubyLLM some time ago asking for A2A support. They'd done their homework: checked the scope, read the contributing guide, linked the spec and an existing Ruby implementation. The case was reasonable: multi-agent setups might cross host boundaries, and A2A seems like the way to do that. First comment from another contributor: "Love this one."

So I went and read the spec. All of it. The Agent Cards, the task lifecycle, the JSON-RPC layer, the capability negotiation. And the whole time I kept thinking: I can already do this.

```ruby
class Researcher < RubyLLM::Agent
  chat_model Chat
  instructions "You are an expert researcher. Be concise and factual."
end

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

class Assistant < RubyLLM::Agent
  instructions "Use the research tool for factual questions. Pass the chat_id to follow up with the same researcher."
  tools ResearchTool
end
```

That's it. First call, `chat_id` is nil, a new researcher is spawned. The tool returns the result *and* the `chat_id`. Next time the assistant needs to follow up, it passes the `chat_id` back, and the researcher picks up where it left off. Full conversation history persisted. Agents decide which context to pass each other. 20 lines of [RubyLLM](https://rubyllm.com) code.

That's persistent conversation, shared state, ongoing collaboration, and capability discovery. **With an optional parameter on a tool.**

This is why I don't think a protocol is the right solution; a convention is. And if someone wants A2A badly enough, it can live as a community extension, the same way [ruby_llm-mcp](https://github.com/patvice/ruby_llm-mcp) does. But it doesn't belong in the core.

Why? Every protocol comes with metadata, capability schemas, and negotiation overhead that ends up as tokens in your window. A2A doesn't just add complexity to your architecture. It adds complexity to your context.

## The pattern

I've watched this happen with Big Data, with microservices, with Kubernetes. Every time, a real need gets wrapped in so much ceremony that people forget the problem was simple to begin with. Most apps that "needed" Hadoop could have used a SQL database. Most companies that "needed" microservices needed a well-organized monolith. Most deployments that "needed" Kubernetes needed a single server and a deploy script.

Build what you need. Skip the ceremony.
