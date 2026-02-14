---
layout: post
title: "RubyLLM 1.12: Agents Are Just LLMs with Tools"
date: 2026-02-17
description: "Agents aren't magic. They're LLMs that can call your code. RubyLLM 1.12 adds a clean DSL to define and reuse them."
tags: [Ruby, AI, Agents, LLM, Ruby on Rails, Open Source, Tool Calling, RubyLLM]
image: /images/rubyllm-1.12.png
---

"Agent" might be the most overloaded word in tech right now. Every startup claims to have one. Every framework promises to help you build them. The discourse has gotten so thick that the actual concept is buried under layers of marketing.

So let's start from first principles.

## What's an Agent?

An agent is an LLM that can call functions.

That's it. When you give a language model a set of tools it can invoke -- a database lookup, an API call, a file operation -- and the model decides when and how to use them, you have an agent. The model reasons about the problem, picks the right tool, looks at the result, and continues reasoning. Sometimes it calls several tools in sequence. Sometimes none.

There's no special "agent mode." No orchestration engine. No graph of nodes. It's just a conversation where the model can do things besides talk.

## RubyLLM Always Had This

Tool calling has been a core feature of [RubyLLM][rubyllm] since 1.0:

```ruby
class SearchDocs < RubyLLM::Tool
  description "Searches our documentation"
  param :query, desc: "Search query"

  def execute(query:)
    Document.search(query).map(&:title)
  end
end

chat = RubyLLM.chat
chat.with_tool(SearchDocs)
chat.ask "How do I configure webhooks?"
# Model searches docs, reads results, answers the question
```

That's an agent. The model decides to search, interprets the results, and responds. You didn't need a special class or framework to make this happen.

But there was a problem.

## The Reuse Problem

In a real application, you don't configure a chat once. You configure it in controllers, background jobs, service objects, API endpoints. The same instructions, the same tools, the same temperature -- scattered across your codebase:

```ruby
# In the controller
chat = RubyLLM.chat(model: 'gpt-4.1')
chat.with_instructions("You are a support assistant for #{workspace.name}...")
chat.with_tools(SearchDocs, LookupAccount, CreateTicket)
chat.with_temperature(0.2)

# In the background job
chat = RubyLLM.chat(model: 'gpt-4.1')
chat.with_instructions("You are a support assistant for #{workspace.name}...")
chat.with_tools(SearchDocs, LookupAccount, CreateTicket)
chat.with_temperature(0.2)

# In the service object...
# You get the idea
```

Every Rubyist's instinct kicks in: this should be a class.

## RubyLLM 1.12: A DSL for Agents

That's exactly what 1.12 adds. Define your agent once, use it everywhere:

```ruby
class SupportAgent < RubyLLM::Agent
  model 'gpt-4.1'
  instructions "You are a concise support assistant."
  tools SearchDocs, LookupAccount, CreateTicket
  temperature 0.2
end

# Anywhere in your app
response = SupportAgent.new.ask "How do I reset my API key?"
```

Every macro maps to a `with_*` call you already know. `model` maps to `RubyLLM.chat(model:)`. `tools` maps to `with_tools`. `instructions` maps to `with_instructions`. No new concepts. Just a cleaner way to package what you were already doing.

## Runtime Context

Static configuration is only half the story. Real agents need runtime data -- the current user, the workspace, the time of day. Agents support lazy evaluation for this:

```ruby
class WorkAssistant < RubyLLM::Agent
  chat_model Chat
  inputs :workspace

  instructions { "You are helping #{workspace.name}" }

  tools do
    [
      TodoTool.new(chat: chat),
      GoogleDriveTool.new(user: chat.user)
    ]
  end
end

chat = WorkAssistant.create!(user: current_user, workspace: @workspace)
chat.ask "What's on my todo list?"
```

Blocks and lambdas are evaluated at runtime, with access to the chat object and any declared inputs. Values that depend on runtime context must be lazy -- a constraint that Ruby makes trivially natural.

## Prompt Conventions

If you're using Rails, agents follow a convention for prompt management:

```ruby
class WorkAssistant < RubyLLM::Agent
  chat_model Chat
  instructions display_name: -> { chat.user.display_name_or_email }
end
```

This renders `app/prompts/work_assistant/instructions.txt.erb` with `display_name` available as a local. Namespaced agents map naturally: `Admin::SupportAgent` looks in `app/prompts/admin/support_agent/`.

Your prompts are ERB templates. Version them in git. Review them in PRs. Treat them like the application code they are.

## Rails Integration

The `chat_model` macro activates Rails-backed persistence:

```ruby
class WorkAssistant < RubyLLM::Agent
  chat_model Chat
  model 'gpt-4.1'
  instructions "You are a helpful assistant."
  tools SearchDocs, LookupAccount
end

# Create a persisted chat with agent config applied
chat = WorkAssistant.create!(user: current_user)

# Load an existing chat, apply runtime config
chat = WorkAssistant.find(params[:id])

# User sends a message, everything persisted automatically
chat.ask(params[:message])
```

`create!` persists both the chat and its instructions. `find` applies configuration at runtime without touching the database. This distinction matters when your prompts evolve faster than your data.

## Also in 1.12

Agents are the headline, but this release also adds:

- **AWS Bedrock full coverage** via the Converse API -- every Bedrock chat model through one interface
- **Azure Foundry API** -- broad model access across Azure's ecosystem
- **Clearer `with_instructions` semantics** -- explicit append options, guaranteed message ordering

## Already in Production

This isn't a spec or a proposal. The agent DSL powers [Chat with Work](https://chatwithwork.com) in production right now. The `WorkAssistant` examples above aren't hypothetical -- they're simplified versions of real code handling real conversations.

If you want to see what it feels like, [try it out](https://chatwithwork.com).

## The Point

The industry is making agents complicated. They're not. An agent is an LLM with tools. You define the tools in Ruby. You package them in a class. You use the class in your app.

No graphs. No chains. No orchestration frameworks. Just Ruby.

```ruby
gem 'ruby_llm', '~> 1.12'
```

[rubyllm]: https://rubyllm.com
