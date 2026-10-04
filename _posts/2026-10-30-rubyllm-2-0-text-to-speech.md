---
layout: post
title: "Text to speech in RubyLLM 2.0"
date: 2026-10-30
description: "RubyLLM 2.0 adds RubyLLM.speak: pick a voice and format, stream the audio, and pair it with streaming, diarized transcription."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
image: /images/rubyllm-2.0-text-to-speech.png
---

```ruby
RubyLLM.speak("Hello, welcome to RubyLLM!").save("welcome.mp3")
```

RubyLLM has had transcription since 1.x. 2.0 adds text to speech with `RubyLLM.speak`.

I've wanted this pair for a while. With both, a Ruby app can take a voice message, have a model answer it, and reply with audio, using one library and one config block instead of a different SDK for each step.

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

A Rails controller can answer with audio in one line:

```ruby
send_data speech.to_blob, type: speech.mime_type, disposition: "inline"
```

`save` and `to_blob` are the same methods you use on generated images, videos, and downloaded files.

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

OpenAI, Gemini, ElevenLabs, Deepgram, Mistral, xAI, Azure, Vertex AI, OpenRouter, and GPUStack all answer to `speak`. Voices are provider-specific: OpenAI and Gemini use names, ElevenLabs uses voice IDs from your voice library, and Deepgram bakes the voice into the model name. Leave `voice:` out and you get the provider's default.

Formats differ too. Gemini returns raw PCM, so `speech.format` is `"pcm"`, and giving the file a `.wav` name doesn't turn it into WAV. Run it through ffmpeg when you need a container.

## Tell It How to Sound

`model:`, `voice:`, and `format:` are keywords because every provider has them. Everything else goes in `provider_options:`, in the provider's own words:

```ruby
RubyLLM.speak(
  "The red panda has merged to main.",
  provider_options: { instructions: "Sound proud, but not smug.", speed: 1.1 }
)
```

ElevenLabs takes `voice_settings`. Gemini takes direction in the prompt itself ("Say cheerfully: ..."). I chose to pass each provider's own options through rather than invent a lowest-common-denominator `emotion:` parameter that would cover only part of what each one supports.

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

The whole round trip fits in a Rails action:

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

Check that the upload is actually a file: a bare string parameter would make RubyLLM read a path or fetch a URL you didn't intend. The middle step is a normal chat, so it can use tools, approvals, and history like any other. The three steps run one after another as ordinary requests; there's no realtime audio stream here.

## Streaming and Diarized Transcription

Transcripts stream now:

```ruby
transcription = RubyLLM.transcribe("standup.wav", model: "gpt-4o-transcribe") do |chunk|
  print chunk.delta if chunk.delta?
end

transcription.text # the complete transcript
```

Chunks tell you what they carry: `delta?` for committed text, `partial?` for a tentative guess that the next one replaces, `segment?` for speaker and timing data. Deepgram, ElevenLabs, xAI, and Google's live models stream over WebSockets with the optional `websocket-driver` gem; OpenAI, Mistral, and others stream over plain HTTP. Either way, the input is a recording you already have.

Speaker labels now work beyond OpenAI. Pass `speaker_names:` and models across providers label who said what:

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
