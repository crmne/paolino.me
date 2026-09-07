---
layout: post
title: "Video, OCR, Reranking, and Tokenization in RubyLLM 2.0"
description: "RubyLLM 2.0 adds video generation, document OCR, reranking, tokenization, and token counting with Ruby methods and typed results."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

I like APIs where the method tells you what you're about to get. `paint` gives you an image. `transcribe` gives you text from audio.

RubyLLM 2.0 adds video generation, document OCR, reranking, tokenization, and token counting with the same approach.

## Animate

```ruby
video = RubyLLM.animate("A red panda typing on a mechanical keyboard")
video.save("panda.mp4")
```

That submits a video job and polls until the provider finishes. The returned `RubyLLM::Video` saves the completed clip. Choose a supported model with `model:`; the API stays the same across providers.

`animate` waits, so put it in a background job in a web app. If you'd rather schedule the polling yourself, submit with `animate_later`:

```ruby
job = RubyLLM.animate_later("A paper boat floating down a rainy gutter")

# Later, when checking the provider's progress:
job.refresh
job.video.save("boat.mp4") if job.completed?
```

`job.done?` includes failures; `completed?` means the video succeeded. `job.wait` runs the polling loop for you.

Despite the similar names, `animate_later` and `ask_later` do different things: the first submits a remote job immediately, while the second only stages a chat message. Image-to-video models also accept a reference through `with:`.

## OCR

```ruby
ocr = RubyLLM.ocr("contract.pdf")

ocr.pages.each do |page|
  puts "Page #{page.index + 1}"
  puts page.markdown
end

ocr.markdown # all pages joined
```

OCR accepts supported documents and images as local files, IO objects, or public URLs. Mistral handles PDFs, office documents, and images; Cohere Parse handles one image per request.

`pages:` is a RubyLLM keyword with zero-based page indexes. Mistral's extra options belong in `provider_options:`:

```ruby
ocr = RubyLLM.ocr(
  "annual-report.pdf",
  pages: [0, 1, 2],
  provider_options: { table_format: "html", include_image_base64: true }
)
```

Pages expose extracted markdown, images, tables, and the raw page data. That's useful for a document pipeline before you even ask a chat model a question.

## Rerank

Embeddings can retrieve a set of likely documents. A reranker reads the query against each candidate and orders the results by relevance:

```ruby
rerank = RubyLLM.rerank(
  "What is Ruby?",
  ["Paris is the capital of France.", "Ruby is a programming language."],
  model: "rerank-v3.5"
)

result = rerank.results.first
result.document
result.score
result.index # position in the original array
```

`model:` is required; reranking has no default model. Pass `provider:` when you need to select a hosted deployment explicitly.

`top_n:` limits the results returned. Use `index` to map each result back to the record you supplied. Scores belong to the chosen model; they aren't comparable probabilities across rerankers.

Where the provider reports tokens or a charge, read `rerank.tokens` and `rerank.cost`. Cohere bills reranking in search units, so a token-based total can be `nil`.

## Inspect Token IDs

```ruby
tokens = RubyLLM.tokenize("Ruby makes AI useful.", model: "grok-4.3")
tokens.ids
tokens.count
```

`RubyLLM::Tokenization` contains the IDs in text order. It tokenizes the supplied string, so it doesn't include chat formatting, tools, or attachments. Token IDs depend on the chosen model.

## Count Tokens Before Generation

You can also size a request before asking the model to answer:

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5")
  .with_instructions(big_system_prompt)
  .with_tools(Search)

input_tokens = chat.count_tokens("Summarize this contract.")
```

The count includes history, instructions, function tools, schemas, thinking settings, and attachments that the counting endpoint supports. Passing a question for counting doesn't append it to the chat. Server tools, provider options, compaction, and `before_request` edits aren't forwarded to counting endpoints, so those settings can make the generated request differ.

For a standalone prompt, call `RubyLLM.count_tokens(text, model:)`. Tokenization and request counting use different endpoints; the [coverage matrix](https://rubyllm.com/next/provider-coverage/) shows availability. Unsupported operations raise `RubyLLM::Error`. Neither count predicts the output length or replaces the usage reported after generation.

These are the features that used to send me looking for another SDK. I'm glad they can now sit beside the chat code. The guides cover [video](https://rubyllm.com/next/video-generation/), [OCR](https://rubyllm.com/next/ocr/), [reranking](https://rubyllm.com/next/rerank/), and [tokenization and counting](https://rubyllm.com/next/tokenization/).
