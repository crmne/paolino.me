---
layout: post
title: "Ruby Is the Best Language for Building AI Apps"
date: 2026-02-20
description: "A pragmatic, code-first argument for Ruby as the best language to ship AI products in 2026."
tags: [Ruby, Rails, AI, LLM, RubyLLM, Async, Developer Experience]
image: /images/rubyconfth-2026-keynote.jpg
video: https://www.youtube.com/embed/fAHif8MNCfw?si=L1ZXT690lXcB-0Lu
---

> If your goal is to ship AI applications in 2026, Ruby is the best language to do it.

## The AI Training Ecosystem Is Irrelevant

Python owns model training. PyTorch, TensorFlow, the entire notebooks-and-papers gravity well. Nobody disputes that.

But you're not training LLMs. Almost nobody is. Each training run costs millions of dollars. The dataset is the internet!

This is what AI development today looks like:

```bash
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model": "gpt-5.2", "messages": [{"role": "user", "content": "Hello"}]}'
```

That's it. An HTTP call.

The entire Python ML stack is _irrelevant_ to achieve this. What matters is everything around it: streaming responses to users, persisting conversations, tracking costs, switching providers when pricing changes.

That's web application engineering. That's where Ruby and Rails shine like no other.

## "You Need a Complex Agent Framework or You're Not Doing Real AI"

Bullshit.

You need a beautiful, truly provider-independent API. Let me show you.

## Python vs JavaScript vs Ruby LLM Libraries

### Simple chat

**Python (LangChain):**

```python
from langchain.chat_models import init_chat_model
from langchain.messages import HumanMessage

model = init_chat_model("gpt-5.2", model_provider="openai")
response = model.invoke([HumanMessage("Hello!")])
```

You need to specify the provider, create an array of messages that need to be instantiated, etc.

That's ceremony.

**JavaScript (AI SDK):**

```javascript
import { generateText } from 'ai';
import { openai } from '@ai-sdk/openai';

const { text } = await generateText({
  model: openai('gpt-5.2'),
  prompt: 'Hello!',
});
```

What if you want to use a model from another provider?

**Ruby ([RubyLLM][]):**

```ruby
require 'ruby_llm'

RubyLLM.chat.ask "Hello!"
```

Reads like it should.

### Token usage tracking

If you're running AI in production, you need to track token usage. This is how you price your app.

**LangChain (GPT):**

```python
response = model.invoke([HumanMessage("Hello!")])
response.response_metadata['token_usage']
# {'completion_tokens': 12, 'prompt_tokens': 8, 'total_tokens': 20}
```

**LangChain (Claude):**

```python
response.response_metadata['usage']
# {'input_tokens': 8, 'output_tokens': 12}
```

Different key and different structure!

**LangChain (Gemini):**

```python
response.response_metadata
# ...nothing...
```

It's not even there!

[RubyLLM][]:

```ruby
response.tokens.input   # => 8
response.tokens.output  # => 12
```

Same interface. Every provider. Every model.

### Agents

This is where it gets fun.

**Python (LangChain):**

```python
from langchain_openai import ChatOpenAI
from langchain.agents import create_agent

model = ChatOpenAI(model="gpt-5-nano")

graph = create_agent(
    model=model,
    tools=[search_docs, lookup_account],
    system_prompt="You are a concise support assistant",
)

inputs = {"messages": [{"role": "user", "content": "How do I reset my API key?"}]}

for chunk in graph.stream(inputs, stream_mode="updates"):
    print(chunk)
```

**JavaScript (AI SDK 6):**

```javascript
import { ToolLoopAgent } from 'ai';
import { openai } from '@ai-sdk/openai';

const supportAgent = new ToolLoopAgent({
  model: openai('gpt-5-nano'),
  system: 'You are a concise support assistant.',
  tools: { searchDocs, lookupAccount },
});

const { text } = await supportAgent.generateText({
  messages: [{ role: 'user', content: 'How do I reset my API key?' }],
});
```

**Ruby ([RubyLLM][]):**

```ruby
require 'ruby_llm'

class SupportAgent < RubyLLM::Agent
  model "gpt-5-nano"
  instructions "You are a concise support assistant."
  tools SearchDocs, LookupAccount
end

SupportAgent.new.ask "How do I reset my API key?"
```

Pure joy.

## It's About Cognitive Overhead

This isn't just about aesthetics.

It's about *cognitive overhead*: how many abstractions, how many provider-specific details, how many different data structures you need to hold in your head instead of focusing on what really matters: prompts and tool design.

Low cognitive overhead compounds: faster onboarding, fewer accidental bugs, easier refactors, and cleaner debugging when production explodes at 2AM.

Ruby's advantage here is cultural: elegant APIs are treated as first-class engineering work, not icing on the cake.

## Rails Gives You the Rest of the Product for Free

Model calls are only a small chunk of your code. The rest makes up the bulk of it: auth, billing, background jobs, streaming UI, persistence, admin screens, observability, even [native apps](https://native.hotwired.dev/).

Rails gives you a beautiful, coherent answer for all of it.

With [RubyLLM][] + Rails, the core streaming loop is tiny:

```ruby
class ChatResponseJob < ApplicationJob
  def perform(chat_id, content)
    chat = Chat.find(chat_id)

    chat.ask(content) do |chunk|
      message = chat.messages.last
      message.broadcast_append_chunk(chunk.content) if chunk.content.present?
    end
  end
end
```

And on the model side:

```ruby
class Chat < ApplicationRecord
  acts_as_chat
end

class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments
end
```

This gives you streaming chunks to your web app and persistence in your DB in absurdly few lines of code.

## It Scales

"Ruby can't handle AI scale."

Wrong.

LLM workloads are mostly network-bound and streaming-bound. That's exactly where Ruby's [Async](https://socketry.github.io/async/) ecosystem shines. Fibers let you handle high concurrency without thread explosion and resource waste. No need to plaster the code with `async`/`await` keywords. [RubyLLM][] became concurrent with 0 code changes.

I wrote a deep dive here: [Async Ruby is the Future of AI Apps (And It's Already Here)](/async-ruby-is-the-future)

## Don't Take My Word for It

Someone ported [RubyLLM][]'s API design to JavaScript as [NodeLLM](https://github.com/nicholasgriffintn/node-llm). Same design. Clean code, good docs.

The JavaScript community's response: zero upvotes on Reddit. 14 GitHub stars. Top comments: "How's this different from AI SDK?" and "It's always fun when you AI bros post stuff. They all look and sound the same. Also, totally unnecessary."

[RubyLLM][]: #1 on Hacker News. ~3,600 stars. 5 million downloads. Millions of people using RubyLLM-powered apps today.

Same design. Wildly different reception. That tells you everything about which community is ready for this moment.

And teams that switched from Python are not going back:

> We had a customer deployment coming up and our Langgraph agent was failing. I rebuilt it using [RubyLLM][]. Not only was it far simpler, it performed better than the Langgraph agent.

> Our first pass at the AI Agent used langchain... it was so painful that we built it from scratch in Ruby. Like a cloud had lifted. Langchain was that bad.

> At Yuma, serving over 100,000 end users, our unified AI interface was awful. [RubyLLM][] is so much nicer than all of that.

These aren't people who haven't tried Python. They tried it, shipped it, and replaced it.

## Go Ship AI Apps with Ruby, Rails, and [RubyLLM][]

When we freed ourselves from complexity, this community built Twitter, GitHub, Shopify, Basecamp, Airbnb. Rails changed web development forever.

Now we have the chance to change AI app development. Because AI apps are all about the product. And nobody builds products better than Ruby developers.

[RubyLLM]: https://rubyllm.com
