---
layout: post
title: "The Standard API for LLM Capabilities and Pricing is Now Live"
date: 2025-05-13
description: "The API we wished existed is now a reality. No more hunting through docs for model information."
tags: [Ruby, AI, LLM, API Standards, OpenAI, Anthropic, Gemini, DeepSeek, Open Source, Parsera]
image: /images/standard-llm-capabilities-pricing-api-live.png
---

## The API We Always Wanted is Finally Here

Remember that frustration of hunting through documentation to find basic model information? That's over. The LLM Capabilities API I announced last month is now live, and it's already transforming how developers work with AI models.

[Check out the model browser](https://llmspecs.parsera.org/) or [dive straight into the API](http://api.parsera.org/v1/llm-specs).

## The Problem We Solved

It's 2025, and until now, you still couldn't get basic information about LLM models through their APIs. Want to know the context window? Pricing per token? Whether a model supports function calling? You had to dig through documentation that changes constantly and is formatted differently for each provider.

This wasn't just annoying. It was actively harmful. Developers wasted countless hours maintaining this information manually. Library maintainers were duplicating effort across the ecosystem. Applications broke when pricing changed without notice.

## From Frustration to Solution

We've been maintaining model capabilities and pricing in [RubyLLM][rubyllm] since the beginning. But as the ecosystem exploded with new models and providers, manual maintenance became untenable. Every time OpenAI, Anthropic, or Google changed their pricing or released a new model, we were back to updating capabilities files.

So I partnered with [Parsera][parsera] to build something better: a standardized API that provides capabilities and pricing information for all major LLM providers.

## The API in Action

The schema we designed captures everything developers need:

```yaml
id: gpt-4o-mini
name: GPT-4o mini
provider: openai
context_window: 128000
max_output_tokens: 16384

modalities:
  input:
    - text
    - image
  output:
    - text

capabilities:
  - function_calling
  - structured_output
  - streaming
  - batch

pricing:
  text_tokens:
    standard:
      input_per_million: 0.15
      output_per_million: 0.6
      cached_input_per_million: 0.075
```

The [full API](http://api.parsera.org/v1/llm-specs) tracks:
- Context windows and token limits
- Input/output modalities (text, image, audio)
- Available capabilities (function calling, structured output, batch, etc.)
- Detailed pricing for standard and batch operations
- Special pricing for cached inputs and reasoning tokens

## Already Integrated in RubyLLM

We've already integrated this into [RubyLLM 1.3.0][rubyllm-release]. When you run `RubyLLM.models.refresh!`, you're pulling from the Parsera API - getting continuously updated data scraped directly from provider websites.

```ruby
# Refresh model information from the API
RubyLLM.models.refresh!

# Use the data programmatically
model = RubyLLM.models.find("gpt-4.1-nano")
puts model.context_window        # => 1047576
puts model.capabilities          # => ["batch", "function_calling", "structured_output"]
puts model.pricing.text_tokens.standard.input_per_million  # => 0.1
```

## For the Entire Ecosystem

This isn't just for RubyLLM. The API is open to everyone. Whether you're building in Python, JavaScript, or any other language, you can access the same standardized data.

Check out the [model browser](https://llmspecs.parsera.org/) to explore what's available. Use the [API directly](http://api.parsera.org/v1/llm-specs) in your applications. No more duplicated effort. No more outdated information. Just a single source of truth.

## Next Steps

The API is live and serving real traffic. We're continuously expanding coverage and improving accuracy. Found a bug or missing model? [Report it on the GitHub tracker](https://github.com/parsera-labs/api-llm-specs/issues).

In the longer term, we hope providers will adopt this standard directly - this shouldn't require scraping. But for now, we've solved the immediate problem. Model information is finally accessible, standardized, and always current.

What do you think? How are you using the API? Let me know on [GitHub Discussions](https://github.com/crmne/ruby_llm/discussions) or in the [bug tracker](https://github.com/parsera-labs/api-llm-specs/issues).

[rubyllm]: https://rubyllm.com
[rubyllm-release]: /rubyllm-1-3
[parsera]: https://parsera.org