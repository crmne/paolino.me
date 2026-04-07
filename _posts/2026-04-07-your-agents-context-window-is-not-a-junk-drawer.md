---
layout: post
title: "Your Agent's Context Window Is Not a Junk Drawer"
date: 2026-04-07
description: "Most of what's in your agent's context window shouldn't be there."
tags: [AI, LLM, MCP, Agents, Developer Experience]
image: /images/context-rot.png
---

Your agent's context window is the most precious resource it has. The more you stuff into it, the worse your agent performs.

Researchers call it [context rot](https://research.trychroma.com/context-rot): the more tokens in the window, the harder it becomes for the model to follow instructions, retrieve information, and stay on task. Chroma tested 18 frontier models and found that accuracy drops up to 30% when you go from a focused 300-token input to 113k tokens of conversation history, with the task held constant. The model essentially became _dumber_.

This holds true regardless of how big the window is, yet most agent setups treat the context window like a junk drawer.

"Just toss it in there, the LLM will figure it out!"

## MCP: the biggest offender

Don't get me wrong. MCP is a fine idea. You need to talk to a service? Grab an MCP server, plug it in, and you're running in ten minutes. For prototyping, for exploration, for answering "is this even worth building?", it's great.

The problem is what happens next. Which is: nothing.

People leave the MCP servers plugged in. They add more. Every MCP server you connect dumps tool descriptions, schemas, and instructions into your context. You didn't write those. You didn't optimize them. You probably haven't even read them. You're handing over a chunk of your context window to whatever some third party decided to shove in there.

Say you need a tool that checks the weather. You could plug in an MCP server and get dozens of tool descriptions, parameter schemas, and whatever instructions its author decided to write. Or you could write this:

```ruby
class Weather < RubyLLM::Tool
  description "Gets current weather for a location"

  param :latitude, desc: "Latitude (e.g., 52.5200)"
  param :longitude, desc: "Longitude (e.g., 13.4050)"

  def execute(latitude:, longitude:)
    url = "https://api.open-meteo.com/v1/forecast?latitude=#{latitude}&longitude=#{longitude}&current=temperature_2m,wind_speed_10m"
    Faraday.get(url).body
  rescue => e
    { error: e.message }
  end
end
```

Twelve lines of [RubyLLM](https://rubyllm.com). You wrote the description, so you know exactly what tokens are going into your context. You wrote the parameters, so the model gets precisely the interface it needs, no more. You own it, you can tune it, and nobody can inject anything into your agent's brain through it.

Use MCP to prototype. Then replace it with crafted tools you actually control.

## Tool responses are context too

Your RAG retrieves ten full documents when the model needs a paragraph. Your API call returns a massive JSON blob when the model needs two fields. You're paying for every one of those tokens with your agent's IQ.

The fix is progressive disclosure. At [Chat with Work](https://chatwithwork.com), when the agent searches your Google Drive, we don't dump entire files into context. The search tool returns only some metadata and a single line from the file, the line that matched the search keywords. Fifty results, fifty lines. The AI reads those, decides which files actually matter, and only then reads them. If a file is too large, it reads it in chunks. At every step, the model is only looking at what it needs.

The same principle applies to any tool. Don't return everything. Return enough for the model to decide what to look at next.

## Your instructions are context too

Then there's the stuff you wrote yourself. Your system prompt is context. Your tool descriptions are context. Your parameter schemas are context. Every edge case, every guardrail, every overly detailed description competes for attention. You think you're being thorough. You're actually drowning the instructions that matter in a sea of instructions that don't. A focused system prompt will outperform an exhaustive one every time.

## Tool count is context too

You hand-crafted 40 beautiful tools. Your agent needs 5 for this task. The other 35 sit in context doing nothing except making the model slower at picking the right one.

Don't register every tool your agent might ever need. Load the tools the current task actually requires. If you're building a support agent that handles billing and technical issues, don't give it all of both. Route billing questions to a billing toolset and technical questions to a technical toolset. Two focused agents will outperform one bloated one.

## Every token should earn its place

The context window is not a junk drawer. It's a workbench. Everything on it should be there for a reason, and you should be able to say what that reason is.

So before you plug in another MCP server, add another RAG source, or write another paragraph in your system prompt, ask yourself one question: is this worth making my agent dumber?

Because that's the trade you're making. Every time.
