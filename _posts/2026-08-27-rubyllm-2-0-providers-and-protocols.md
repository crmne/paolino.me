---
layout: post
title: "RubyLLM 2.0: Providers, Protocols, and Provider Gems"
date: 2026-08-27
description: "OpenAI moves to the Responses API by default, while a new provider architecture and gem generator make external providers first-class."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
sendfox_campaign_id: 3008312
---
RubyLLM 2.0 is almost ready. It isn't out yet, but it will be soon, and I have been looking forward to showing you what is in it.

There is a lot in this release. Too much for one enormous announcement, and most of it deserves more than a bullet point. So this is the first in a series of posts about what's coming in RubyLLM 2.0.

Let's start with providers and protocols.

In 2.0, OpenAI uses the Responses API by default. Providers and protocols are separate things. Four new providers bring the total to seventeen. And if the provider you need is still missing, a new generator gives you a complete provider gem to start from.

```ruby
RubyLLM.chat(model: 'gpt-5.4')                              # OpenAI Responses API
RubyLLM.chat(model: 'gpt-5.4', protocol: :chat_completions) # same model, old API
RubyLLM.chat(model: 'claude-opus-4-6', provider: :vertexai) # Vertex AI, Anthropic protocol
```

## A provider is not a protocol

A provider is the service you connect to: OpenAI, Mistral, Vertex AI, or one of the others. It knows the host, credentials, configuration, and model catalog.

A protocol is the API it speaks: Chat Completions, Responses, Anthropic, Gemini, Bedrock Converse, or Cohere. It knows how to build a request, parse the response, and handle streaming.

Mistral, DeepSeek, Perplexity, Ollama, and most self-hosted services all speak some version of OpenAI's Chat Completions API. In 1.x, I handled that with inheritance. `Mistral < OpenAI` reused the request code, but it also inherited a pile of OpenAI assumptions and then had to undo the ones that did not apply.

That was only half the problem. One protocol can be used by many providers, but one provider can also speak many protocols. OpenAI speaks Chat Completions and Responses; Vertex AI speaks Gemini, Claude, Mistral, and open models, all through different API shapes. The old design had no good way to express that.

In 2.0, providers register the protocols they speak and choose one for each model. Here is the actual routing in the Vertex AI provider:

```ruby
class VertexAI < Provider
  protocol :gemini, VertexAI::Gemini
  protocol :anthropic, VertexAI::Anthropic
  protocol :mistral, VertexAI::Mistral
  protocol :chat_completions, VertexAI::ChatCompletions

  def protocol_for(model, **)
    case model.id
    when %r{/} then protocols[:chat_completions]
    when /\Aclaude/ then protocols[:anthropic]
    when VertexAI::Mistral::MODELS then protocols[:mistral]
    else super
    end
  end
end
```

So Claude on Vertex AI speaks Anthropic. `meta/llama-3.3-70b-instruct-maas` speaks Chat Completions. Gemini speaks Gemini. The model changes, the wire format changes, and your application does not.

## OpenAI uses Responses by default

OpenAI now has two chat APIs. RubyLLM 2.0 supports both, but defaults to Responses.

That means reasoning models can use tools and extended thinking together, which Chat Completions (in OpenAI) cannot express. It also gives RubyLLM access to newer OpenAI features without adding special cases to the old API.

If you still need Chat Completions, choose it for one chat:

```ruby
chat = RubyLLM.chat(model: 'gpt-5.4', protocol: :chat_completions)
```

Or keep it as the default for OpenAI:

```ruby
RubyLLM.configure do |config|
  config.openai_protocol = :chat_completions
end
```

An explicit `protocol:` wins over configuration, and configuration wins over the provider default.

The same protocol code is useful outside OpenAI. xAI's primary API now looks like Responses, so its RubyLLM provider gets streaming, encrypted reasoning, and server tools from the same implementation. Azure and DeepSeek can opt into Responses too.

## One Bedrock endpoint, three APIs

AWS Bedrock Mantle makes the difference between a provider and a protocol very obvious. You connect to one AWS service, but the API changes with the model.

Claude uses Anthropic's Messages API. Five models use OpenAI's Responses API. The other forty-one use Chat Completions. They all live in the same catalog, behind the same authentication, on the same host.

Even the model catalogs disagree. Mantle spells some model IDs differently from Bedrock Converse and includes models that Converse does not know about at all.

Without protocol routing, switching models can also mean switching request formats. RubyLLM reads both catalogs, records which protocol each model speaks, and routes the request for you. The `RubyLLM.chat` API stays the same. You can even switch models in the middle of a conversation with `.with_model`, and RubyLLM switches protocols with it.

## Four new providers

RubyLLM 2.0 will ship with seventeen providers, up from thirteen in 1.16:

* **Cohere** with native chat, embeddings, reranking, and transcription.
* **Ollama Cloud** with Ollama's API against its hosted model catalog. No local server required.
* **ElevenLabs** for speech and transcription.
* **Deepgram** for speech and transcription.

## A complete provider in one small file

Once the protocol handles the wire format, a provider can be very small. Here is the entire Mistral provider in RubyLLM 2.0:

```ruby
module RubyLLM
  module Providers
    class Mistral < Provider
      protocol :chat_completions, ChatCompletions, batches: Mistral::ChatCompletions::Batches
      protocol :files, Protocols::Mistral::Files

      def api_base
        @config.mistral_api_base || 'https://api.mistral.ai/v1'
      end

      def headers
        {
          'Authorization' => "Bearer #{@config.mistral_api_key}"
        }
      end

      class << self
        def capabilities
          Mistral::Capabilities
        end

        def models_dev_alias(...)
          Mistral::Models.models_dev_alias(...)
        end

        def configuration_options
          %i[mistral_api_key mistral_api_base]
        end

        def configuration_requirements
          %i[mistral_api_key]
        end
      end
    end
  end
end
```

That's the whole file. Most providers are between 35 and 100 lines. The longer ones are doing real provider-specific work, like Google authentication or AWS request signing.

## Build the next provider yourself

The provider and protocol split pays off outside RubyLLM too. The most common feature request is another provider. In 2.0, you do not have to wait for me to add one.

```bash
ruby_llm provider-gem Acme --api-base https://api.acme.ai/v1
```

That command creates `ruby_llm-providers-acme`, initializes Git, installs the bundle, and gives you an ignored `.env`, provider registration, a model-catalog task, live-recording specs, RuboCop, Flay, ArchSpec, and CI across every supported Ruby version. It gets the same kind of care as RubyLLM itself, already wired up.

The important part is what you do not have to build. If Acme speaks Chat Completions, it reuses RubyLLM's existing protocol for requests, responses, streaming, tools, and errors. If it speaks another familiar API, pass `--dialect responses`, `anthropic`, `gemini`, `converse`, or `ollama`. The provider only needs to supply its host, authentication, model catalog, and any real quirks it has.

That is what the split makes possible. A new or smaller provider no longer needs another OpenAI-compatible implementation, another Anthropic-compatible implementation, or a growing pile of API-base switches and provider exceptions inside RubyLLM. It gets to reuse the protocol and remain a small adapter.

When it is ready, tell your users to add it to their Gemfile:

```ruby
gem 'ruby_llm-providers-acme', require: 'ruby_llm/providers/acme'
```

With their API key configured, that is it. The gem registers itself, brings its model catalog, and works through the same `RubyLLM.chat` API as a built-in provider.

Once 2.0 is out, go ahead and try it yourself. I'll save the complete tutorial for another post.

## A model registry applications can rely on

The model registry that RubyLLM uses for capabilities and pricing is now published at [rubyllm.com/models.json](https://rubyllm.com/models.json).

For the first time, anyone can download, inspect, or build on the same catalog RubyLLM uses itself.

[models.dev](https://models.dev) is an excellent source, but RubyLLM needs more than a copy of it. Every six hours, RubyLLM rebuilds its registry from models.dev and the providers' own APIs, reconciles aliases, fills gaps, applies the few provider-specific corrections that remain, validates the result, and refuses suspicious regressions before publishing it.

This is not just a model directory for the documentation. RubyLLM applications use it every day to validate model names, choose protocols, check capabilities, and turn provider usage into real costs. That last part demands precision: if a price, modality, or capability is wrong, the answer your application gets is wrong too. I will cover the cost ledger in another post, but the registry is what makes it possible.

```ruby
RubyLLM.models.refresh!
```

`refresh!` fetches the latest main registry and persists it. New models, prices, context windows, and capabilities can reach your application without waiting for the next gem release.

Provider gems can ship their own `models.json` too. RubyLLM loads it as a read-only fallback behind the main registry, so installing a provider gem is enough to use its models normally:

```ruby
RubyLLM.chat(model: 'MiniMax-M3').ask('Hello')
```

The global `refresh!` never refreshes or rewrites provider gem catalogs. Their authors update them with `rake models` inside the provider gem.

The important part is that none of this makes the public API more complicated. `RubyLLM.chat`, `embed`, `paint`, and the Rails integration still work the same way. Most people will simply get better provider coverage. The new `protocol:` option is there for the times when you want to choose.

That is the first piece of RubyLLM 2.0. Next up: the agentic loop, and how 2.0 lets you stop it, resume it, and run it one step at a time.

The full guide to writing providers and protocols is at [rubyllm.com/next/custom-providers](https://rubyllm.com/next/custom-providers/).
