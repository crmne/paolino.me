---
layout: post
title: "Files and Attachments in RubyLLM 2.0"
date: 2026-10-28
description: "RubyLLM 2.0 uploads a file once and reuses it, moves large attachments to provider storage for you, and lets tools return files."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

If a user asks five questions about the same 40 MB PDF, sending those 40 MB five times is silly. Upload it once:

```ruby
manual = RubyLLM.upload("manual.pdf", provider: :anthropic)

chat = RubyLLM.chat(model: "claude-sonnet-5")
chat.ask "Summarize the manual.", with: manual
chat.ask "What does the warranty cover?"

RubyLLM.chat(model: "claude-sonnet-5").ask "Which page explains the reset button?", with: manual
```

The requests point at the provider's copy. `with:` takes an uploaded file exactly like a path or a URL, so the rest of your code doesn't care where the bytes live.

This saves you the transfer, not the tokens. The model still reads the document on every request; [prompt caching](https://rubyllm.com/prompt-caching/) is what makes re-reading it cheap.

## One Upload API

`RubyLLM.upload` takes a path, an IO, or a `RubyLLM::Attachment`, and returns a `RubyLLM::UploadedFile`:

```ruby
file.id
file.provider
file.filename
file.byte_size
file.mime_type
file.expires_at
```

OpenAI and Azure want a `purpose:`; IOs want a `filename:`:

```ruby
file = RubyLLM.upload(io, provider: :openai, purpose: "user_data", filename: "manual.pdf")
```

Leave out `provider:` and RubyLLM uses the provider of your default model. If you store file IDs, store the provider next to them. A file ID means nothing without the provider that issued it:

```ruby
file = RubyLLM::UploadedFile.find(record.file_id, provider: record.file_provider)
```

Files come back out the same way generated images, speech, and video do:

```ruby
RubyLLM.download(file_id, provider: :openai).save("report.pdf")
```

`download` returns a `RubyLLM::DownloadedFile` with `save` and `to_blob`. It's also a plain Ruby String, so you can hand it straight to a CSV parser. Download rules are the provider's: Anthropic and OpenRouter, for example, only let you download files their tools created, not the PDF you uploaded.

Twelve providers have file APIs behind this, including S3 for Bedrock and Cloud Storage for Vertex AI, where `uri:` picks the object. Fewer can reference a stored file from a chat, so pick a model that accepts what you uploaded.

## Large Attachments Upload Themselves

Most of the time you won't call `upload` at all. Attach the file like you always have:

```ruby
chat = RubyLLM.chat(model: "gemini-3.7-flash")
chat.ask "What happens in this screencast?", with: "screencast.mp4"
```

If the file is too big to send inline, RubyLLM uploads it to the provider and sends a reference instead. Gemini switches over at 20 MB (7 MB on Vertex AI), Anthropic at 24 MB, OpenAI at 50 MB for PDFs and documents. Vertex AI and Bedrock stage the file in the bucket you configured with `vertexai_batch_gcs_uri` or `bedrock_batch_s3_uri`.

The upload is remembered on the attachment, per provider and per set of credentials. Ask a follow-up and the chat reuses it. Switch the chat to another provider and it uploads once there. Let it expire and RubyLLM uploads a fresh copy. Your local history keeps the original file, so none of this leaks into your transcript.

The memo lives in memory, though. A Rails chat reloaded in another process uploads its stored file again; 2.1 records those uploads in a table so it doesn't have to.

If you'd rather manage uploads yourself:

```ruby
RubyLLM.configure do |config|
  config.auto_upload_large_files = false
end
```

## Tools Can Hand Back Files

A tool shouldn't have to describe a chart in words. In 2.0 it can return the chart:

```ruby
class RevenueChart < RubyLLM::Tool
  description "Renders a revenue chart for a quarter"
  parameter :quarter, description: "Quarter, like 2026-Q3"

  def execute(quarter:)
    path = Charts.revenue(quarter).render_png
    ["Revenue chart for #{quarter}", RubyLLM::Attachment.new(path)]
  end
end
```

Strings become the tool result's text and attachments become its files. Return a bare `RubyLLM::Attachment` for a file-only result. A search tool can return the documents it found; a browser tool can return a screenshot of the page it's looking at. Vision models then look at them, which is the whole point.

Every provider wants tool files in a different shape. Anthropic and Bedrock take them inside the tool result, Gemini 3 inside the function response, and OpenAI, whose tool results are text-only, gets them in a user message right after the result. You write the return value once; RubyLLM does the translating. If a provider can't take that file type at all, you get `RubyLLM::UnsupportedAttachmentError` rather than a model quietly answering about a file it never saw.

I'm especially looking forward to the tools people build with this. An agent that can look at what its tools produced is a lot less likely to make things up about it.

The [files guide](https://rubyllm.com/files/) covers expiration, provider limits, and storage setup, and the [attachments guide](https://rubyllm.com/attachments/) covers everything `with:` accepts.
