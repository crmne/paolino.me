---
layout: post
title: "Ruby Is the Best Language for Building AI Apps"
date: 2026-02-10
description: "A pragmatic, code-first argument for Ruby as the best language to ship AI products in 2026."
tags: [Ruby, Rails, AI, LLM, RubyLLM, Async, Developer Experience]
---

After more than a decade building ML systems in Python, saying this feels mildly heretical:

> If your goal is to ship AI applications in 2026, Ruby is the best language to do it.

Not because Python is bad. Not because JavaScript is dying. Not because Ruby magically became the fastest runtime.

Because the bottleneck moved.

The bottleneck is no longer model training for most teams. It's product engineering: how quickly you can turn model APIs into reliable user features, and how long your codebase stays understandable once the first demo works.

Ruby is absurdly good at that job.

## The Important Distinction: Training vs Shipping

Let's start with the obvious objection.

Python still owns model training and research:

- PyTorch
- JAX
- the entire notebooks-and-papers gravity well

If you're training custom models or doing heavy research workflows, use Python. End of debate.

But most startups and product teams are not training foundation models. They're integrating OpenAI, Anthropic, Gemini, Mistral, Bedrock, OpenRouter, and local endpoints into web products.

For that reality, your day-to-day work looks like this:

1. Pick a model
2. Define prompts and tools
3. Stream responses to users
4. Persist conversations and attachments
5. Track tokens/costs/errors
6. Switch providers when quality/price changes

That's web application engineering with an AI-shaped API in the middle.

Ruby and Rails were built for exactly this category of problem.

## Why This Argument Matters Now

Three years ago, saying "use Ruby for AI" sounded nostalgic.

Now we have:

- mature model APIs
- standardized patterns (chat, tools, structured output, embeddings)
- production Ruby libraries designed around those patterns
- enough usage data to evaluate what scales and what explodes

So this is no longer "can Ruby do AI?"

It can.

The real question is: which ecosystem gives you the best leverage per line of code?

## A Concrete Comparison (Python vs JavaScript vs Ruby)

The fastest way to make this discussion useful is to compare real operations you'll implement in week one.

### 1. Simple chat

Python (LangChain):

```python
from langchain.chat_models import init_chat_model
from langchain.messages import HumanMessage

model = init_chat_model("gpt-5.2", model_provider="openai")
response = model.invoke([HumanMessage("Hello!")])
```

JavaScript (AI SDK):

```javascript
import { generateText } from 'ai';
import { openai } from '@ai-sdk/openai';

const { text } = await generateText({
  model: openai('gpt-5.2'),
  prompt: 'Hello!',
});
```

Ruby (RubyLLM):

```ruby
RubyLLM.chat.ask "Hello!"
```

The point isn't line-count golfing. It's mental overhead.

In Ruby, the API reads like the use case.

### 2. Multi-turn conversation

Python:

```python
messages = [HumanMessage("Hello!")]
response = model.invoke(messages)
messages.append(response)
messages.append(HumanMessage("Tell me more."))
model.invoke(messages)
```

JavaScript:

```javascript
const messages = [{ role: 'user', content: 'Hello!' }];
const first = await generateText({ model, messages });
messages.push({ role: 'assistant', content: first.text });
messages.push({ role: 'user', content: 'Tell me more.' });
await generateText({ model, messages });
```

Ruby:

```ruby
chat = RubyLLM.chat
chat.say "Hello!"
chat.ask "Tell me more."
```

Again: less plumbing, fewer ways to accidentally mess up state handling.

### 3. Streaming

Python:

```python
for chunk in model.stream("Write a poem about Ruby"):
    print(chunk.text)
```

JavaScript:

```javascript
const result = streamText({ model: openai('gpt-5.2'), prompt: 'Write a poem' });
for await (const part of result.fullStream) {
  if (part.type === 'text-delta') process.stdout.write(part.textDelta);
}
```

Ruby:

```ruby
RubyLLM.chat.ask("Write a poem about Ruby") do |chunk|
  print chunk.thinking
  print chunk.content
end
```

Ruby blocks are doing real work here. Streaming feels native instead of bolted-on.

### 4. Multi-modality

Python often means manually fetching/encoding files and constructing provider-specific payloads.

Ruby:

```ruby
RubyLLM.chat.ask "Describe the weather in this image:",
                 with: "https://example.com/sunny.jpg"
```

Or mixed media:

```ruby
RubyLLM.chat.ask "Analyze these files", with: [
  "diagram.png",
  "meeting.mp3",
  "report.pdf"
]
```

This is where many "AI frameworks" get noisy. Ruby's interface stays quiet.

### 5. Structured output

Python:

```python
from dataclasses import dataclass

@dataclass
class Person:
    name: str
    age: int
    hobbies: list[str]

person = model.with_structured_output(Person).invoke("Generate a person")
```

JavaScript:

```javascript
const { object } = await generateObject({
  model: openai('gpt-5.2'),
  schema: z.object({
    name: z.string(),
    age: z.number(),
    hobbies: z.array(z.string()),
  }),
  prompt: 'Generate a person.',
});
```

Ruby:

```ruby
class PersonSchema < RubyLLM::Schema
  string :name
  integer :age
  array :hobbies, of: :string
end

person = RubyLLM.chat.with_schema(PersonSchema).ask "Generate a person"
```

A DSL that feels like Ruby, not like JSON-with-extra-steps.

### 6. Tool calling

Python/JS versions are workable, but typically pull you into bigger config structures quickly.

Ruby:

```ruby
class Weather < RubyLLM::Tool
  description "Get current weather"
  param :latitude
  param :longitude

  def execute(latitude:, longitude:)
    # call API here
  end
end

RubyLLM.chat.with_tool(Weather).ask "Weather in Bangkok?"
```

When you need nested params, retries, fallbacks, and multiple tools, this API shape pays off fast.

## This Is Not About Syntax Sugar

A common Hacker News reaction to posts like this is:

"Cool syntax, but syntax doesn't matter at scale."

Correct. Syntax alone doesn't matter.

What matters is *surface area*:

- how many abstractions you need to hold in your head
- how many provider-specific details leak into app code
- how often your team copies framework boilerplate instead of writing product logic

Low surface area compounds.

It means faster onboarding, fewer accidental bugs, easier refactors, and cleaner debugging when production goes weird at 2AM.

Ruby's advantage here is cultural and technical: elegant APIs are treated as first-class engineering work, not icing.

## Rails Gives You the Rest of the Product for Free

AI teams often underestimate this part.

The model call is easy. The rest is hard:

- auth
- billing
- background jobs
- streaming UI
- persistence
- admin screens
- observability

Rails gives you a coherent answer for all of it.

With RubyLLM + Rails, the core streaming loop is tiny:

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

That gets you production-grade primitives quickly, without inventing your own mini-framework.

## Vendor Churn Is Real. Ruby Handles It Cleanly.

Model quality and pricing are moving targets.

If your architecture hardcodes provider shape everywhere, you'll pay migration tax every quarter.

A unified abstraction layer is not a luxury anymore. It's risk management.

RubyLLM's model registry and provider abstraction let you:

- switch providers without rewriting business logic
- inspect capabilities and costs from one place
- avoid lock-in theater before it becomes lock-in debt

## The Scale Question

Another predictable objection:

"Ruby can't handle AI scale."

The old version of this argument was already weak. For AI apps specifically, it's increasingly wrong.

LLM workloads are mostly network-bound and streaming-bound. That's exactly where Ruby's async ecosystem is strongest. Fibers and cooperative I/O let you handle high concurrency without thread explosion and resource waste.

I wrote a full deep dive here: [Async Ruby is the Future of AI Apps (And It's Already Here)](https://paolino.me/async-ruby-is-the-future)

The short version: if your bottleneck is long-lived I/O, Async Ruby is a very serious tool.

## Fair Criticisms (And When Not to Choose Ruby)

Ruby is not the right answer for everything.

Don't pick Ruby if:

- your core moat is model training research
- your org is already deeply invested in a Python platform team with excellent internal tooling
- you need niche research libraries that only exist in Python

Do pick Ruby if:

- you're building AI-enabled web products
- speed of product iteration matters more than notebook ergonomics
- you care about long-term maintainability as much as demo speed

That's most product companies.

## Why Ruby Communities Produce Better AI Product Code

This is the least quantifiable part, but maybe the most important.

Ruby culture treats programmer happiness and code aesthetics as engineering concerns. That sounds soft until you watch teams ship.

Teams writing code they actually enjoy reading move faster.

Teams with clean interfaces keep momentum after launch.

Teams that value clarity can make bolder product bets because the codebase doesn't fight back.

In AI, where everyone is racing and every stack is changing monthly, this is an edge.

## The Bet

If you're choosing a stack for a new AI product in 2026, you can optimize for one of two things:

1. fitting in with the default choice
2. shipping better software with less complexity

The default choice is easy to justify in meetings.

The second choice wins in production.

Ruby gives you leverage.
Rails gives you velocity.
RubyLLM gives you a clean interface to a messy ecosystem.

AI apps are web apps.

And Ruby is still the best language for building web apps.
