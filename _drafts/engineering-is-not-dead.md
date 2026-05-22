---
layout: post
title: "Engineering Is Not Dead Because Accountability Is Not"
date: 2026-05-22
description: "Models can generate the code. They cannot be accountable for it. The real distinction is whether the result is owned."
tags: [AI, LLM, Software Development, Taste]
---

A lot of people have developed a gag reflex against anything touched by AI.

I understand where that comes from. There is a lot of slop, maintainers are tired of reviewing code from people who do not understand it, and people are tired of [predictable cadence](https://x.com/jorgemanru/status/2053183727514091820).

We're also heading towards a version of the future where all code will be generated. The models are good enough that for a lot of work, especially the boring repetitive kind, typing everything by hand makes very little sense. You can describe what you want, steer the model, ask for changes, review the output, and get to a working implementation much faster than before.

That caused some people to make the jump from "models can generate code" to "engineering is dead".

That's wrong.

## Code Generation Is Not Engineering

Engineering is not the act of producing text that happens to run or compile.

Engineering is deciding what should exist. Understanding the constraints. Knowing what can go wrong. Making trade-offs. Reviewing the result. Being responsible for what happens after you ship it.

The model can write the code. Most of it. Maybe all of it. But the model can't be the author, because the model is not accountable.

You are.

If a generated library has a security issue, people will not open an issue against the model. They will open it against you. If a generated feature behaves badly in production, your reputation will suffer. If the code is impossible to maintain six months later, the model is not at fault.

You are.

This is why your engineering skills matter more than ever. Since you are not spending most of your time typing, you can focus on what really matters.

## So How Do You Tell?

The discussion around AI-generated code is confused because people focus too much on the origin.

Lots of good code will be touched by LLMs. So will code from your favorite programmers. So will lots of bad code.

The involvement of AI tells you very little by itself.

The real distinction is whether the result is owned or not. It is the care, attention, review, testing, product design, and engineering the author put into it.

You signal it by producing high-quality output and being accountable for it. By showing up. By fixing bugs. By knowing your own code inside and out. By making it clear that there is a person behind the work who understands the result and accepts responsibility for it.

That takes care, taste, engineering skill, and genuine human effort.

This goes both ways. The same skills are needed by people evaluating code and products. It is not enough to ask whether AI was involved. You have to look at the result, the behavior, the tests, the edge cases, the maintenance story, and the author’s ability to own the thing.

Engineering is not dead, because accountability is not.
