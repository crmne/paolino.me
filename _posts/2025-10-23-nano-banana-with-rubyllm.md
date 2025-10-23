---
layout: post
title: "Nano Banana with RubyLLM"
date: 2025-10-23
description: "Nano Banana hides behind Google's chat endpoint. Here's the straight line to ship it with RubyLLM."
tags: [Ruby, AI, RubyLLM, Google, Gemini]
image: /images/nano-banana.png
---

Providers sometimes make curious choices. Take Nano Banana: Google wired it into the chat interface `generateContent`, not the image API's `predict`.

This is counterintuitive especially if you're using RubyLLM which makes you think in terms of _actions_ like [`paint`](https://rubyllm.com/image-generation/), instead of [`chat`](https://rubyllm.com/chat/).

The good news is that RubyLLM makes it super easy to use once you know that quirk. Only caveat: as of writing this post, you need the latest trunk or v1.9+ in the future, because that's where we taught it how to unpack inline file data from chat responses.

## Wire It Up

```ruby
chat = RubyLLM
         .chat(model: "gemini-2.5-flash-image")
         .with_temperature(1.0) # optional, but you like creativity, right?
         .with_params(generationConfig: { responseModalities: ["image"] }) # also optional, if you prefer the model to return only images

response = chat.ask "your prompt", with: ["all.png", "the.jpg", "attachments.png", "you.png", "want.jpg"]

image_io = response.content[:attachments].first.source
```

That `StringIO` holds the generated image. Stream it to S3, attach it to Active Storage, or keep it in memory for a downstream processor.

Want a file?

```ruby
response.content[:attachments].first.save "nano-banana.png"
```

That's it. Chat endpoint, one call. Ship the image feature and go enjoy the rest of your day.
