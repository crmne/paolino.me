---
layout: post
title: "RubyLLM 2.0: Prompts Live in app/prompts"
date: 2026-11-06
description: "RubyLLM 2.0 renders ERB prompts from app/prompts anywhere, lets agents find their instructions by convention, and lets Rails engines ship prompts."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
image: /images/rubyllm-2.0-prompt-templates.png
---

A two-page prompt inside a Ruby heredoc is hard to work with. The prompt changes often, the class around it rarely does, and every diff is paragraphs of English between `def` and `end`.

RubyLLM 2.0 adds `RubyLLM.render_prompt`:

```erb
<%# app/prompts/support/instructions.txt.erb %>
You are a support assistant for <%= product_name %>.
The current customer is <%= customer_name %>.
Answer with concise, practical steps.
```

```ruby
instructions = RubyLLM.render_prompt(
  "support/instructions",
  product_name: "BillingHub",
  customer_name: current_user.name
)

RubyLLM.chat
  .with_instructions(instructions)
  .ask("How do I update my invoice email?")
```

It reads an ERB file, renders it with your locals, and returns a String. It doesn't call a model or create a chat. Use the string as instructions, as a user message, as the input to `RubyLLM.embed`, anywhere you need text.

Prompts are templates, so they get a directory the way views do: `app/prompts`, next to `app/views`.

## How Lookup Works

`"support/instructions"` resolves to `app/prompts/support/instructions.txt.erb`, relative to `Rails.root` in Rails and to the current directory in plain Ruby. Nested directories work the way you'd expect, and you can pass the full filename if you prefer.

Every keyword argument becomes a local. Reference a local you didn't pass and ERB raises. Ask for a file that doesn't exist and you get `RubyLLM::PromptNotFoundError`. Since rendering is just a method that returns a String, you can test every prompt without an API key.

Prompt files are code. ERB runs Ruby, so keep prompt names in your code and pass user input only as locals, never as the name.

## Agents Find Their Own Instructions

Agents have used `app/prompts` since [1.12](/rubyllm-1-12-agents/). They now use the same renderer as `RubyLLM.render_prompt`, and in 2.0 a named agent picks up its prompt without being told:

```ruby
class WorkAssistant < RubyLLM::Agent
  chat_model Chat
end
```

If `app/prompts/work_assistant/instructions.txt.erb` exists, that's the system prompt. `Admin::SupportAgent` looks in `app/prompts/admin/support_agent/`. If there's no file, the agent starts without instructions, and an empty file means no instructions rather than an empty system message. That's why `bin/rails generate ruby_llm:agent Support` gives you `app/agents/support_agent.rb` without an `instructions` line, and an empty `app/prompts/support_agent/instructions.txt.erb` waiting for you to write in it.

When the prompt is required, say so, and a missing file raises:

```ruby
class WorkAssistant < RubyLLM::Agent
  chat_model Chat
  instructions { prompt("instructions") }
end
```

When it needs runtime data, pass locals. Lambdas run when the agent applies its configuration, with access to the chat and the agent's inputs. The template also gets `chat` and every declared input as locals for free:

```ruby
class WorkAssistant < RubyLLM::Agent
  chat_model Chat
  inputs :workspace

  instructions display_name: -> { chat.user.display_name_or_email },
               workspace_name: -> { workspace.name }

  instructions append: true, persist: false do
    "Today is #{Date.current}."
  end
end
```

That second declaration is new in 2.0 too. Instructions can stack, and `persist: false` keeps the date out of the saved transcript, so a chat loaded on a later day gets the current date instead of a stale one.

If you upgraded from 1.x: a bare `instructions` call used to mean "require my conventional prompt". In 2.0 it's just the reader. Use `instructions { prompt("instructions") }` when you want the old strictness.

## Changing a Prompt Under Existing Chats

A Rails-backed agent saves its instructions when `create!` makes the chat. `WorkAssistant.find(id)` applies the current configuration for that run without rewriting what's saved. That's deliberate: loading a chat shouldn't rewrite its saved history.

When you do want old conversations to pick up the new wording:

```ruby
WorkAssistant.sync_instructions(chat)
```

It re-renders the agent's persisted instructions and saves them on the chat. Run it over whichever conversations should move. (In 1.x this was `sync_instructions!`; 2.0 drops the bang.)

## Prompts From an Engine

This one came from [@adrianthedev](https://github.com/adrianthedev), who wanted a Rails engine to ship its own prompts. `RubyLLM::Prompt.roots` is the ordered list of prompt directories, the same idea as Action View's view paths. The app's `app/prompts` is always first. An engine appends its own:

```ruby
module MyEngine
  class Engine < ::Rails::Engine
    initializer "my_engine.prompts" do
      RubyLLM::Prompt.roots << MyEngine::Engine.root.join("app/prompts")
    end
  end
end
```

An agent the engine ships finds `my_engine/chat_agent/instructions.txt.erb` in the engine. The host app overrides it by creating `app/prompts/my_engine/chat_agent/instructions.txt.erb`, the same way you'd override an engine's view.

Thanks to [@kryzhovnik](https://github.com/kryzhovnik), who extracted the renderer out of Agent's private methods, which made this possible. Partials in 2.1 are also @kryzhovnik's work: `<%= render "tone", display_name: display_name %>` inside a prompt pulls in `_tone.txt.erb`, the way it would in a view.

The [prompt rendering guide](https://rubyllm.com/prompt-rendering/) has the details, and the [agents guide](https://rubyllm.com/agents/) covers the class-based conventions.
