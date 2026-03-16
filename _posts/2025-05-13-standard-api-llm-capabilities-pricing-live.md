---
layout: post
title: "The LLM Capabilities and Pricing API is Live"
date: 2025-05-13
description: "The standard API for LLM model information I announced last month is now live and already integrated into RubyLLM 1.3.0."
tags: [Ruby, AI, LLM, API Standards, OpenAI, Anthropic, Gemini, DeepSeek, Open Source, Parsera]
image: /images/standard-llm-capabilities-pricing-api-live.png
---

*Update: The Parsera API has been sunsetted. RubyLLM now uses [models.dev](https://models.dev) for model capabilities and pricing.*

The [LLM Capabilities API](/standard-api-llm-capabilities-pricing) I announced last month is live. [Browse the models](https://llmspecs.parsera.org/) or [hit the API directly](http://api.parsera.org/v1/llm-specs).

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

[Parsera][parsera] scrapes provider docs and keeps the data current. Context windows, pricing, capabilities, and modalities are all in one place.

## Already in RubyLLM

[RubyLLM 1.3.0][rubyllm-release] pulls from this API directly:

```ruby
RubyLLM.models.refresh!

model = RubyLLM.models.find("gpt-4.1-nano")
puts model.context_window        # => 1047576
puts model.capabilities          # => ["batch", "function_calling", "structured_output"]
puts model.pricing.text_tokens.standard.input_per_million  # => 0.1
```

The API is open to everyone: any language, any framework. Found a missing model? [Report it](https://github.com/parsera-labs/llm-specs/issues).

Providers should expose this data themselves. Until they do, this works.

[rubyllm]: https://rubyllm.com
[rubyllm-release]: /rubyllm-1-3
[parsera]: https://parsera.org
