---
layout: post
title: "Files and Attachments in RubyLLM 2.0"
description: "Upload reusable provider files, automatically upload eligible large attachments, and return files from Ruby tools in RubyLLM 2.0."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

If a user asks five questions about the same PDF, I'd rather upload it once than send its bytes with every request.

RubyLLM 2.0 adds provider-managed files:

```ruby
file = RubyLLM.upload("manual.pdf", provider: :anthropic)

chat = RubyLLM.chat(model: "claude-sonnet-4-5")
chat.ask "Summarize the manual.", with: file

another_chat = RubyLLM.chat(model: "claude-sonnet-4-5")
another_chat.ask "What does the warranty cover?", with: file
```

The requests refer to the uploaded file. You can reuse it while the provider retains it, subject to the selected model's file support.

This saves transferring the document again. It doesn't by itself cache the model's input tokens; [prompt caching](/rubyllm-2-0-prompt-caching/) handles that separately.

## Uploads Have One API

`RubyLLM.upload` takes a path, an IO object, or a `RubyLLM::Attachment` and returns an `UploadedFile`:

```ruby
file.id
file.provider
file.filename
file.byte_size
file.mime_type
file.expires_at
```

For an IO, pass `filename:`. OpenAI and Azure also require `purpose:`:

```ruby
file = RubyLLM.upload(
  "manual.pdf",
  provider: :openai,
  purpose: "user_data"
)
```

Omitting `provider:` uses the provider of `config.default_model`. For code that stores file IDs, I prefer to make the provider explicit and save it alongside the ID:

```ruby
file = RubyLLM::UploadedFile.find(file_id, provider: :anthropic)
```

Downloaded files have the same saving API as generated images, audio, and video:

```ruby
RubyLLM.download(file_id, provider: :openai).save("report.pdf")
```

The result is a `RubyLLM::DownloadedFile`, with `to_blob` for bytes. It is also a Ruby String, so parsers and `each_line` work directly. Download permissions depend on the file: Anthropic only allows downloads of files created server-side, not the PDF you uploaded yourself.

File APIs and chat file references are separate capabilities. RubyLLM supports file operations on more providers than it supports attaching stored files to chat. Check that the selected chat model accepts the kind of stored file you uploaded.

## Large Local Attachments Can Upload Automatically

For normal attachments, `with:` still works:

```ruby
chat = RubyLLM.chat(model: "gemini-2.5-flash")
chat.ask "What happens in this video?", with: "screencast.mp4"
```

On Gemini, eligible local attachments above 20 MB are uploaded through its Files API and referenced by URI. Anthropic and OpenAI have their own thresholds and supported types. RubyLLM does this only for providers and protocols that can reference the uploaded file in chat.

Vertex AI and Bedrock can stage large attachments in your own cloud storage. They need a configured `vertexai_batch_gcs_uri` or `bedrock_batch_s3_uri`; Vertex AI also needs `google-cloud-storage`. Those bucket settings apply to large attachments as well as batches.

To manage uploads yourself:

```ruby
RubyLLM.configure do |config|
  config.auto_upload_large_files = false
end
```

You can also choose a cloud-storage destination explicitly with `RubyLLM.upload(..., uri: "gs://...")` or an S3 URI. `content_type:` overrides MIME detection; provider-specific fields go in `provider_options:`.

## Tools Can Hand Back Files

A document search tool shouldn't have to turn every result into a string. In 2.0, it can return an attachment with its text:

```ruby
class DocumentSearch < RubyLLM::Tool
  description "Searches the company drive"
  parameter :query, description: "What to look for"

  def execute(query:)
    doc = Drive.search(query).first
    return "No matching document found." unless doc

    ["Found: #{doc.name}", RubyLLM::Attachment.new(doc.download_path)]
  end
end
```

A chart tool can return the chart. A browser tool can return a screenshot. A file-only result can be a bare `RubyLLM::Attachment`.

RubyLLM renders those files using the selected protocol's supported format. Some protocols accept media inside tool results; others need a following user message to carry it. Unsupported attachment types raise `RubyLLM::UnsupportedAttachmentError`.

I'm especially looking forward to tools that return something the model can look at. The [files guide](https://rubyllm.com/next/files/) covers provider limits, expiration, and storage setup.
