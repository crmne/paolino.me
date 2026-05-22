# Engineering Is Not Dead

There is a version of the future where most code is generated.

Honestly, we are already entering it. The models are now good enough that for a lot of work, especially the boring repetitive work, it makes very little sense to type everything by hand. You can describe what you want, steer the model, ask for changes, review the output, and get to a working implementation much faster than before.

That is real, and it is not going away.

But I keep seeing people jump from “models can generate code” to “engineering is over”, and I think that is wrong.

Because engineering was never just typing.

## Code generation is not engineering

Engineering is not the act of producing text that happens to run, or compile, or pass the happy path.

Engineering is deciding what should exist. It is understanding the constraints. It is knowing what can go wrong. It is making trade-offs. It is reviewing the result. It is thinking about the user, the product, the system, the edge cases, the maintenance cost. And it is being responsible for what happens after you ship it.

The model can write the code. It can write most of it. Maybe, in some cases, it can write all of it.

But the model is not the author in the way that matters, because the model is not accountable.

You are.

If a generated library has a security issue, people will not open an issue against the model. They will open it against you. If a generated feature behaves badly in production, your reputation will suffer. If the code is impossible to maintain six months later, the model is not at fault in any practical sense.

You are.

This is why engineering skills matter more than ever. If you are no longer spending most of your time typing every line by hand, you can spend more of your time doing the actual engineering: understanding the problem, shaping the solution, reviewing the output, improving the design, testing the important paths, and deciding whether the thing is good enough to put your name on.

The work did not disappear. It moved.

And in many ways, it moved to the parts that were always the most important.

## The wrong distinction

The discussion around AI-generated code is often confused.

People talk about it as if the important distinction is whether an LLM touched the code or not. But that is not really the distinction that matters anymore.

These days, lots of good code will be touched by LLMs. Code from your favorite programmers will be touched by LLMs. My code is touched by LLMs. And lots of terrible code will be touched by LLMs too.

The involvement of AI tells you very little by itself.

The real distinction is not human code versus AI code. The real distinction is owned code versus unowned code.

There is a huge difference between asking a model to build something, running it once, seeing that it appears to work, and publishing it, versus using a model as part of a serious engineering process.

In one case, you are outsourcing not only the typing, but also the thinking.

In the other case, you are using the model to move faster through a process that is still yours. You still define the problem. You still bring the taste. You still know what kind of solution you want. You still review the code at the level the situation requires. You still test it. You still decide what is acceptable. You still understand the trade-offs.

That is not the same thing.

And yes, from the outside it can be hard to tell the difference. That is why people are suspicious. We are surrounded by AI slop now, and maintainers, reviewers, and users are right to care. They have all seen code that looks plausible until the person who submitted it cannot explain it, cannot maintain it, and cannot fix it when it breaks.

So the question becomes: how do you signal ownership?

You signal it by showing up. By responding to issues. By knowing your own code. By documenting the parts that are uncertain. By writing tests. By fixing bugs. By avoiding the obvious LLM defaults when they make the work worse. By showing taste. By showing care. By building a reputation over time.

In other words, by being an engineer.

This also means that the people evaluating code need to become better engineers too. It is no longer enough to ask whether something was AI-generated. That question is too shallow. You have to look at the result. You have to look at the design, the behavior, the tests, the failure modes, the maintenance story, and the author’s ability to own the thing.

Some generated code will be excellent. Some handwritten code will be garbage. The origin does not decide the quality. The process does.

## Engineering is still the job

I do not think this is bad news.

Actually, I think it is good news. There is a lot of boring work in programming, even though programming is one of the most fun jobs in the world. I do not want to manually write every adapter, every test scaffold, every obvious refactor, every piece of glue code, just to prove that I suffered enough.

I want to build good things.

Models help with that. Agents help with that. They make me faster. They let me explore more options. They help me learn patterns I might not have reached as quickly on my own. They remove a lot of friction between having an idea and seeing it work.

But they do not remove responsibility.

When the thing leaves your machine and enters the world, it is yours. Your users will treat it as yours. Your customers will treat it as yours. Your contributors will treat it as yours. Your reputation will treat it as yours.

And that is why engineering is not dead.

Because accountability is not dead.

As long as someone has to decide what should exist, what is good enough, what is safe enough, what is maintainable enough, and what they are willing to put their name on, engineering still belongs to people.
