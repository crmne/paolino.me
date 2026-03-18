---
layout: post
title: "A Standard API for LLM Capabilities and Pricing"
date: 2025-04-01
description: "No provider exposes model capabilities and pricing through their API. So we're building one."
tags: [Ruby, AI, LLM, API Standards, OpenAI, Anthropic, Gemini, DeepSeek, Open Source]
image: /images/standard-llm-capabilities-pricing-api.jpg
sendfox_campaign_id: 2750875
---
*Update: The Parsera API has been sunsetted. RubyLLM now uses [models.dev](https://models.dev) for model capabilities and pricing.*

It's 2025, and no LLM provider exposes basic model information through their API. Context window? Pricing per token? Function calling support? You're reading documentation pages that change without notice and look different for every provider.

I've been maintaining this data by hand in [RubyLLM][rubyllm] since the beginning. Every pricing change, every new model: someone updates a file. It doesn't scale. And every other LLM library is doing the same thing independently.

So I partnered with [Parsera][parsera] to build what should have existed from the start: a single API that returns capabilities and pricing for every major LLM.

## The schema

```yaml
id: gpt-4.5-preview                     # Matches the provider's API
display_name: GPT-4.5 Preview
provider: openai
family: gpt45
context_window: 128000
max_output_tokens: 16384
knowledge_cutoff: 20231001

modalities:
  text:
    input: true
    output: true
  image:
    input: true
    output: false
  audio:
    input: false
    output: false
  pdf_input: false
  embeddings_output: false

capabilities:
  streaming: true
  function_calling: true
  structured_output: true
  batch: true
  reasoning: false

pricing:
  text_tokens:
    standard:
      input_per_million: 75.0
      cached_input_per_million: 37.5
      output_per_million: 150.0
    batch:
      input_per_million: 37.5
      output_per_million: 75.0
```

Context windows, token limits, modalities, capabilities, pricing for standard and batch operations. Everything you need to programmatically pick a model and estimate costs.

Parsera handles the scraping. They expose a public GET endpoint. RubyLLM integrates on day one. But this isn't just for RubyLLM; any library in any language can use it.

We're finalizing the schema now: [check out the draft][gist]. Starting with OpenAI, Anthropic, Gemini, and DeepSeek. Feedback welcome in the [Gist comments][gist] or on [GitHub Discussions](https://github.com/crmne/ruby_llm/discussions).

[gist]: https://gist.github.com/crmne/301be1d38ff193e7274a69833947139a
[rubyllm]: https://rubyllm.com
[parsera]: https://parsera.org
