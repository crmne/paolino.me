---
layout: post
title: "Video, OCR, Reranking, and Tokenization in RubyLLM 2.0"
date: 2026-10-09
description: "RubyLLM 2.0 adds animate, ocr, rerank, tokenize, and count_tokens: one Ruby method per job, each returning a typed result."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

```ruby
RubyLLM.animate("A red panda typing on a mechanical keyboard").save("panda.mp4")
```

That generates a video and saves it.

I like APIs where the method tells you what you're about to get. `chat` gives you a conversation, `paint` gives you an image, `embed` gives you vectors. 2.0 adds five more verbs: `animate`, `ocr`, `rerank`, `tokenize`, and `count_tokens`. These are the jobs that used to send me looking for another SDK. Now they sit next to the chat code and follow the same conventions.

## Animate

`animate` submits a video job, polls until the provider finishes, and returns a `RubyLLM::Video`. Video takes a while, so run it in a background job:

```ruby
class PandaTrailerJob < ApplicationJob
  def perform(product)
    video = RubyLLM.animate("A red panda unboxing #{product.name}, studio lighting")

    product.trailer.attach(
      io: StringIO.new(video.to_blob),
      filename: "trailer.mp4",
      content_type: video.mime_type
    )
  end
end
```

`save` and `to_blob` work the same on images, speech, video, and downloaded files, so every media type gives you its bytes the same way.

To animate a still image, pass it through `with:`, the same keyword chats use for attachments:

```ruby
video = RubyLLM.animate(
  "The panda looks up from the keyboard and waves",
  model: "grok-imagine-video",
  with: "panda.png",
  provider_options: { duration: 5 }
)
```

`extend:` continues a video you generated:

```ruby
longer = RubyLLM.animate(
  "The panda hits enter and the build goes green",
  model: "grok-imagine-video",
  extend: video
)
```

If you'd rather not hold a thread while the provider renders, `animate_later` submits the job and returns a `RubyLLM::VideoJob` right away:

```ruby
job = RubyLLM.animate_later("A paper boat floating down a rainy gutter")

# ...do other work...
job.refresh
job.video.save("boat.mp4") if job.completed?
```

`done?` is true once the job finishes either way, `completed?` only when you got a video, and `wait` runs the polling loop for you. Gemini, Vertex AI, xAI, Azure, Bedrock, OpenRouter, ElevenLabs, and GPUStack all sit behind the same call.

## OCR

```ruby
ocr = RubyLLM.ocr("contract.pdf")

ocr.markdown # every page, joined

ocr.pages.each do |page|
  puts "Page #{page.index + 1}"
  puts page.markdown
end
```

You get markdown per page, plus the images and tables the provider found and its raw page data, without involving a chat model. Mistral Document AI reads PDFs, office documents, and images; Cohere Parse reads one image per request.

`pages:` takes zero-based page indexes. Everything Mistral-specific goes in `provider_options:`, in Mistral's own vocabulary:

```ruby
ocr = RubyLLM.ocr(
  "annual-report.pdf",
  pages: [0, 1, 2],
  provider_options: { table_format: "html", include_image_base64: true }
)
```

Page selection is a keyword because every OCR API has the concept. Table formats differ between providers, so they stay in the provider's words.

## Rerank

Embeddings are good at finding fifty documents that might answer a question. They're worse at deciding which five actually do. A reranker reads the query against each candidate and sorts them:

```ruby
rerank = RubyLLM.rerank(
  "Why is the red panda on my keyboard?",
  ["Red pandas are attracted to warm surfaces.",
   "Mechanical keyboards use individual switches.",
   "Red pandas spend most of their day resting."],
  model: "rerank-v3.5",
  top_n: 2
)

result = rerank.results.first
result.document # => "Red pandas are attracted to warm surfaces."
result.score
result.index    # => 0, its position in the array you passed
```

`index` is how you map each result back to your records:

```ruby
query_vector = RubyLLM.embed(query).vectors
candidates = Article.nearest_neighbors(:embedding, query_vector, distance: :cosine).limit(50).to_a
rerank = RubyLLM.rerank(query, candidates.map(&:body), model: "rerank-v3.5", top_n: 5)

best = rerank.results.map { |result| candidates[result.index] }
```

`model:` is required. Reranker catalogs differ per provider, so there's no sensible default to pick for you. Scores belong to the model that produced them: fine for ordering and for a cutoff you tune on your own data, meaningless to compare across rerankers. Cohere, Bedrock, Vertex AI, Azure, OpenRouter, and GPUStack all answer `rerank`, and `rerank.tokens` and `rerank.cost` are there when the provider bills per token.

## Tokenize

Sometimes you need to see what the model sees:

```ruby
tokens = RubyLLM.tokenize("Ruby makes AI useful.", model: "grok-4.3")
tokens.ids   # integer token IDs, in order
tokens.count
```

`tokenize` covers exactly the string you pass: no chat formatting, no tools, no attachments. It runs on xAI, Cohere, and GPUStack.

## Count Tokens Before You Send

The more useful question is usually "how big is this request?" Ask the chat:

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5")
  .with_instructions(big_system_prompt)
  .with_tools(Search)

chat.count_tokens("Summarize this contract.") # => Integer
```

That counts history, instructions, function tools, schema, thinking settings, and supported attachments through the provider's own counting endpoint. The question you pass is counted, not added to the conversation. For a lone prompt, `RubyLLM.count_tokens(text, model:)` does the same without a chat.

Counting endpoints don't receive provider tools, `provider_options`, compaction, or `before_request` edits, so a chat using those can send something slightly different from what you counted. And neither count predicts the output. After generation, `response.tokens` has the actual counts.

Anthropic, OpenAI, Gemini, Vertex AI, and Bedrock count requests; the [provider coverage matrix](https://rubyllm.com/provider-coverage/) has the full picture, and anything unsupported raises `RubyLLM::Error` instead of guessing.

## Read More

The guides go deeper: [video generation](https://rubyllm.com/video-generation/), [OCR](https://rubyllm.com/ocr/), [reranking](https://rubyllm.com/rerank/), and [tokenization](https://rubyllm.com/tokenization/).
