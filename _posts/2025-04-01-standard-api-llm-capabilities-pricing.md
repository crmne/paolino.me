---
layout: post
title: "Introducing a Standard API for LLM Capabilities and Pricing"
date: 2025-04-01
description: "Solving the frustration of hunting through documentation to find basic model information."
tags: [Ruby, AI, LLM, API Standards, OpenAI, Anthropic, Gemini, DeepSeek, Open Source]
image: /images/standard-llm-capabilities-pricing-api.jpg
---

## The LLM capability and pricing mess stops here

It's 2025, and you still can't get basic information about LLM models through their APIs. Want to know the context window? Pricing per token? Whether a model supports function calling? Good luck hunting through documentation that changes constantly and is formatted differently for each provider.

This isn't just annoying. It's actively harmful to the ecosystem. Developers waste countless hours maintaining this information manually or hacking together scrapers to pull it from docs. Library maintainers are duplicating effort across the ecosystem. And ultimately, users suffer from brittle applications when this information becomes outdated.

## We've been maintaining this in [RubyLLM][rubyllm]

We've included model capabilities and pricing in [RubyLLM][rubyllm] since the beginning. It's been essential for our users to programmatically select the right model for their needs and estimate costs.

But as the ecosystem has exploded with new models and providers, this has become increasingly unwieldy to maintain. Every time OpenAI, Anthropic, or Google changes their pricing or releases a new model, we're back to updating tables of data.

## Introducing the LLM Capabilities API

So I'm partnering with [Parsera][parsera] to build something better: a standardized API that provides capabilities and pricing information for all major LLM providers.

The schema looks like this:

```yaml
# This is a YAML file so I can have comments but the API should obviously return an array of models in JSON.
# Legend:
#  Required: this is important to have in v1.
#  Optional: this is still important but can wait for v2.

id: gpt-4.5-preview                     # Required, will match it with the OpenAI API
display_name: GPT-4.5 Preview           # Required
provider: openai                        # Required
family: gpt45                           # Optional, each model page is a family for OpenAI models
context_window: 128000                  # Required
max_output_tokens: 16384                # Required
knowledge_cutoff: 20231001              # Optional

modalities:
  text:
    input: true             # Required
    output: true            # Required
  image:
    input: true             # Required
    output: false           # Required
  audio:
    input: false            # Required
    output: false           # Required
  pdf_input: false          # Optional - from Anthropic and Google
  embeddings_output: false  # Required
  moderation_output: false  # Optional

capabilities:
  streaming: true           # Optional
  function_calling: true    # Required
  structured_output: true   # Required
  predicted_outputs: false  # Optional
  distillation: false       # Optional
  fine_tuning: false        # Optional
  batch: true               # Required
  realtime: false           # Optional
  citations: false          # Optional - from Anthropic
  reasoning: false          # Optional - called Extended Thinking in Anthropic's lingo

pricing:
  text_tokens:
    standard:
      input_per_million: 75.0           # Required
      cached_input_per_million: 37.5    # Required
      output_per_million: 150.0         # Required
      reasoning_output_per_million: 0   # Optional
    batch:
      input_per_million: 37.5           # Required
      output_per_million: 75.0          # Required
  images:
    standard:
      input: 0.0                        # Optional
      output: 0.0                       # Optional
    batch:
      input: 0.0                        # Optional
      output: 0.0                       # Optional
  audio_tokens:
    standard:
      input_per_million: 0.0            # Optional
      output_per_million: 0.0           # Optional
    batch:
      input_per_million: 0.0            # Optional
      output_per_million: 0.0           # Optional
  embeddings:
    standard:
      input_per_million: 0.0            # Required
    batch:
      input_per_million: 0.0            # Required
```

This API will track:
- Context windows and token limits
- Knowledge cutoff dates
- Supported modalities (text, image, audio)
- Available capabilities (function calling, streaming, etc.)
- Detailed pricing for all operations

[Parsera][parsera] will handle keeping this data fresh through their specialized scraping infrastructure, and they'll expose a public API endpoint that anyone can access via a simple GET request. This endpoint will return the complete model registry in the standardized format. RubyLLM will integrate with this API immediately upon release.

## This is for everyone

This isn't just for [RubyLLM][rubyllm]. We want this to become a standard that benefits the entire LLM ecosystem. The API will be accessible to developers using any language or framework.

No more duplicated effort across libraries. No more scrambling when pricing changes. Just a single source of truth that everyone can rely on.

LLM library maintainers can simply query this API to get up-to-date information about all models across providers, rather than each implementing their own scraping and maintenance solutions.

## What's next

We're finalizing the schema now and would love your feedback: [check out the draft here][gist].

Expect the first version of the API to launch in the next few weeks. We'll start with the major providers (OpenAI, Anthropic, Gemini, DeepSeek) and expand from there.

In the longer term, we hope to work directly with providers to ensure this data is always accurate and up-to-date. This shouldn't be something the community needs to scrape - it should be a standard part of how LLM providers communicate with developers.

What do you think? Would this solve a pain point for you? Anything missing from the schema that would be essential for your use cases? Let me know in the [Gist' comments][gist] or on [GitHub Discussions](https://github.com/crmne/ruby_llm/discussions).

[gist]: https://gist.github.com/crmne/301be1d38ff193e7274a69833947139a
[rubyllm]: https://rubyllm.com
[parsera]: https://parsera.org