---
layout: post
title: "Text to speech in RubyLLM 2.0"
description: "Generate speech with RubyLLM.speak, choose provider voices and formats, and combine it with transcription and chat in RubyLLM 2.0."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

RubyLLM could already transcribe audio. In 2.0, it can generate speech too:

```ruby
RubyLLM.speak("Hello, welcome to RubyLLM!").save("welcome.mp3")
```

I have wanted this pair for a while. A Ruby app can take a voice message, ask a chat model to answer it, and send back audio without configuring a different SDK for each step.

## Get the Audio Bytes

`speak` returns a `RubyLLM::Speech`:

```ruby
speech = RubyLLM.speak("Your order has shipped.", model: "gpt-4o-mini-tts")

speech.voice     # => "alloy"
speech.format    # => "mp3"
speech.mime_type # => "audio/mpeg"
speech.to_blob  # raw audio bytes
```

In a Rails controller, you can return the bytes directly:

```ruby
send_data speech.to_blob, type: speech.mime_type, disposition: "inline"
```

The default model comes from `config.default_speech_model`. Pass `model:` and, when needed, `provider:` to choose another.

## Choose a Voice

```ruby
RubyLLM.speak("Welcome back.", model: "gpt-4o-mini-tts", voice: "nova", format: "wav")

RubyLLM.speak(
  "Say warmly: Welcome back.",
  model: "gemini-2.5-flash-preview-tts",
  provider: :gemini,
  voice: "Kore"
)

RubyLLM.speak("The build is green.", model: "eleven_v3", provider: :elevenlabs)
RubyLLM.speak("Your order is ready.", model: "aura-2-thalia-en", provider: :deepgram)
```

Voices are provider-specific. OpenAI and Gemini use names, ElevenLabs uses voice IDs, and Deepgram includes the voice in its model name. RubyLLM chooses a provider default when you omit `voice:`.

The formats differ too. OpenAI supports MP3, WAV, and several others. Gemini's speech endpoint returns PCM, so `speech.format` is `"pcm"`. Saving those bytes with a `.wav` extension won't convert them; use an audio converter when you need a container format.

## Provider Options

Shared choices use keywords such as `model:`, `voice:`, and `format:`. Additional request fields go in `provider_options:`. For OpenAI:

```ruby
speech = RubyLLM.speak(
  "The build is green.",
  model: "gpt-4o-mini-tts",
  provider_options: { instructions: "Sound pleased, without shouting.", speed: 1.1 }
)
```

Gemini steers delivery through the prompt itself. You can switch providers through the same method, but choose voices, formats, and extra options that provider supports.

## Listen, Answer, Speak

In a Rails action, the round trip can look like this:

```ruby
transcription = RubyLLM.transcribe(params[:audio])

reply = RubyLLM.chat
  .with_instructions("You are a support assistant. Keep answers short.")
  .ask(transcription.text)

speech = RubyLLM.speak(reply.content)
send_data speech.to_blob, type: speech.mime_type, disposition: "inline"
```

The middle step can use tools or a persisted conversation like any other chat. This example waits for transcription, then the answer, then speech; it isn't a realtime audio stream.

## Stream the Audio as It Arrives

```ruby
speech = RubyLLM.speak("Your order has shipped.") do |chunk|
  player.write(chunk.data)
end

speech.save("confirmation.mp3")
```

`player` is your application's audio player or output stream. The chunks are consecutive bytes of one recording, and the call still returns the complete `Speech`. You can play the audio as it arrives and save it afterward.

## Streaming Transcription

Transcription itself can stream on supported endpoints:

```ruby
transcription = RubyLLM.transcribe("meeting.wav", model: "gpt-4o-transcribe") do |chunk|
  print chunk.delta
end

transcription.text # the completed transcript
```

Providers without streaming transcription support raise when you pass a block.

Diarization models can label speakers too:

```ruby
transcription = RubyLLM.transcribe(
  "team-meeting.wav",
  model: "gpt-4o-transcribe-diarize",
  speaker_names: ["Alice", "Bob"],
  speaker_references: ["alice-voice.wav", "bob-voice.wav"]
)

transcription.segments.each do |segment|
  puts "#{segment['speaker']}: #{segment['text']}"
end
```

The references are short voice samples. They accept the same supported attachment sources as other file inputs. `format:` selects the provider's transcript format, such as OpenAI's `"srt"` or `"diarized_json"`.

Speech and transcription expose tokens and costs where the provider reports enough information, and emit instrumentation events. The [speech guide](https://rubyllm.com/next/text-to-speech/) and [transcription guide](https://rubyllm.com/next/audio-transcription/) have the model and format details.
