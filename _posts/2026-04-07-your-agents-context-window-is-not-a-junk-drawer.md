---
layout: post
title: "Your Agent's Context Window Is Not a Junk Drawer"
date: 2026-04-07
description: "Most of what's in your agent's context window shouldn't be there."
tags: [AI, LLM, MCP, Agents, Developer Experience]
image: /images/context-rot.png
---

I keep getting the same feature request for RubyLLM: "Add MCP support." I've thought about it for a while now, and I've come to a position that's worth writing down.

## MCP: a useful crutch you should eventually throw away

Let me be clear: MCP is a fine idea. You need to talk to a service? Don't want to write the tool definition yourself? Grab an MCP server, plug it in, and you're running in ten minutes. For prototyping, for exploration, for the "let me see if this is even worth building" phase... it's great!

The problem is what happens next. Which is: nothing. People leave the MCP servers plugged in. They add more. They treat their agent's context window like a junk drawer. Just toss it in there, the LLM will figure it out.

It won't. Or rather, it will, but worse than you think.

Every MCP server you connect dumps tool descriptions, schemas, and instructions into your context. You didn't write those descriptions. You didn't optimize them. You probably haven't even read them. You're handing over a chunk of your strictly limited context window, the most precious resource your agent has, to whatever some third party decided to shove in there.

It's the equivalent of letting strangers put random items on your desk and then wondering why you can't find anything. In the LLM world, we call that [context rot](https://research.trychroma.com/context-rot): the more tokens you stuff into the window, the worse your model performs, regardless of how big the window is.

These aren't just performance problems. They're security problems too. Those tool descriptions are text that gets interpreted by an LLM. You're injecting untrusted content directly into the brain of your agent. Every MCP server is a prompt injection surface you didn't audit.

Here's what I mean. Say you need a tool that checks the weather. You could plug in an MCP server and get whatever tool descriptions, parameter schemas, and instructions its author decided to write. Or you could write this:

```ruby
class Weather < RubyLLM::Tool
  description "Gets current weather for a location"

  param :latitude, desc: "Latitude (e.g., 52.5200)"
  param :longitude, desc: "Longitude (e.g., 13.4050)"

  def execute(latitude:, longitude:)
    url = "https://api.open-meteo.com/v1/forecast?latitude=#{latitude}&longitude=#{longitude}&current=temperature_2m,wind_speed_10m"
    JSON.parse(Faraday.get(url).body)
  rescue => e
    { error: e.message }
  end
end
```

Twelve lines. You wrote the description, so you know exactly what tokens are going into your context. You wrote the parameters, so the model gets precisely the interface it needs, no more. You own it, you can tune it, and nobody can inject anything into your agent's brain through it.

My take is simple: use MCP to prototype. Then replace it with purpose-built tools you actually control. Write the tool descriptions yourself. Keep your context tight. Know exactly what's in there and why.
