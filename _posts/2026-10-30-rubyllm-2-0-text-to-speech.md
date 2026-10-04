---
layout: post
title: "Text to speech in RubyLLM 2.0"
date: 2026-10-30
description: "RubyLLM 2.0 adds RubyLLM.speak: pick a voice and format, stream the audio, and pair it with streaming, diarized transcription."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

```ruby
RubyLLM.speak("Hello, welcome to RubyLLM!").save("welcome.mp3")
```

RubyLLM has been able to listen since 1.x. In 2.0 it can talk back.

I've wanted this pair for a long time. A Ruby app can now take a voice message, have a model answer it, and reply out loud, with one library and one config block instead of three SDKs and a weekend.

## A Speech Is an Object

`speak` returns a `RubyLLM::Speech`:

```ruby
speech = RubyLLM.speak("Your order has shipped.")

speech.model     # => "gpt-4o-mini-tts-2025-12-15"
speech.voice     # => "alloy"
speech.format    # => "mp3"
speech.mime_type # => "audio/mpeg"
speech.to_blob   # raw audio bytes
```

Which means a Rails controller can answer with audio in one line:

```ruby
send_data speech.to_blob, type: speech.mime_type, disposition: "inline"
```

`save` and `to_blob` are the same methods you use on generated images, videos, and downloaded files. Once you've learned one, you've learned them all.

## Pick a Voice

```ruby
RubyLLM.speak("Welcome back.", voice: "nova", format: "wav")

RubyLLM.speak(
  "Say warmly: Welcome back.",
  model: "gemini-3.1-flash-tts-preview",
  voice: "Kore"
)

RubyLLM.speak("The build is green.", model: "eleven_v3", provider: :elevenlabs)
RubyLLM.speak("Your order is ready.", model: "aura-2-thalia-en")
```

OpenAI, Gemini, ElevenLabs, Deepgram, Mistral, xAI, Azure, Vertex AI, OpenRouter, and GPUStack all answer to `speak`. The method is shared; the voices aren't. OpenAI and Gemini use names, ElevenLabs uses voice IDs from your voice library, and Deepgram bakes the voice into the model name. Leave `voice:` out and you get the provider's default.

Formats differ too. Gemini returns raw PCM, so `speech.format` is `"pcm"`, and saving it as `.wav` won't make it one. Run it through ffmpeg when you need a container.

## Tell It How to Sound

`model:`, `voice:`, and `format:` are keywords because every provider has them. Everything else goes in `provider_options:`, in the provider's own words:

```ruby
RubyLLM.speak(
  "The red panda has merged to main.",
  provider_options: { instructions: "Sound proud, but not smug.", speed: 1.1 }
)
```

ElevenLabs takes `voice_settings`. Gemini takes direction in the prompt itself ("Say cheerfully: ..."). I'd rather pass you the provider's real knobs than invent a lowest-common-denominator `emotion:` parameter that does half of what each one can.

## Play It While It Arrives

Pass a block and the audio streams:

```ruby
speech = RubyLLM.speak("Your order has shipped.") do |chunk|
  player.write(chunk.data)
end

speech.save("confirmation.mp3")
```

`player` is whatever your app plays audio through. Each `SpeechChunk` is the next run of bytes of one recording, and the call still returns the complete `Speech`, so you can play first and save after. Gemini's speech endpoint doesn't stream; asking it to raises instead of quietly buffering.

## Listen, Answer, Speak

Here's the whole round trip in a Rails action:

```ruby
def create
  audio = params[:audio]
  return head :bad_request unless audio.is_a?(ActionDispatch::Http::UploadedFile)

  question = RubyLLM.transcribe(audio).text
  answer = Current.user.support_chat.ask(question).content

  speech = RubyLLM.speak(answer)
  send_data speech.to_blob, type: speech.mime_type, disposition: "inline"
end
```

Check that the upload is actually a file: a bare string parameter would make RubyLLM read a path or fetch a URL you didn't intend. The middle step is a normal chat, so it can use tools, approvals, and history like any other. This is request and response, one step after another, not a realtime voice session.

## Transcription Grew Up Too

Transcripts stream now:

```ruby
transcription = RubyLLM.transcribe("standup.wav", model: "gpt-4o-transcribe") do |chunk|
  print chunk.delta if chunk.delta?
end

transcription.text # the complete transcript
```

Chunks tell you what they carry: `delta?` for committed text, `partial?` for a tentative guess that the next one replaces, `segment?` for speaker and timing data. Deepgram, ElevenLabs, xAI, and Google's live models stream over WebSockets with the optional `websocket-driver` gem; OpenAI, Mistral, and others stream over plain HTTP. Either way it's a recording you already have, not a microphone.

Speaker labels are no longer an OpenAI-only trick. Pass `speaker_names:` and models across providers label who said what:

```ruby
transcription = RubyLLM.transcribe(
  "standup.wav",
  model: "gemini-3.5-transcribe",
  speaker_names: [],
  timestamps: :word
)

transcription.words.each do |word|
  puts "#{word['speaker']} at #{word['start']}s: #{word['word']}"
end
```

OpenAI's diarization model can still match voices to names from short reference clips with `speaker_references:`. `format:` asks for the provider's transcript format, such as OpenAI's `"srt"`.

Speech and transcription both report tokens and cost when the provider gives enough to work with, and both emit instrumentation events, so the voice feature shows up in the same dashboards as everything else.

The [text to speech guide](https://rubyllm.com/text-to-speech/) and [transcription guide](https://rubyllm.com/audio-transcription/) have every model, voice, and format.
