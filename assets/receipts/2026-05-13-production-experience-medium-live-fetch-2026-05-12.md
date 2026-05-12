Title: The Rails LLM Stack Is Finally Ready for Production. Here Is What I Learned Shipping It.

URL Source: https://generativeai.pub/the-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c

Published Time: 2026-05-12T08:44:51Z

Markdown Content:
# RubyLLM Turbo Streams Buffering Caused 8-12s Delay in Rails | Medium

[Sitemap](https://generativeai.pub/sitemap/sitemap.xml)

[Open in app](https://play.google.com/store/apps/details?id=com.medium.reader&referrer=utm_source%3DmobileNavBar&source=post_page---top_nav_layout_nav-----------------------------------------)

Sign up

[Sign in](https://medium.com/m/signin?operation=login&redirect=https%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c&source=post_page---top_nav_layout_nav-----------------------global_nav------------------)

[](https://medium.com/?source=post_page---top_nav_layout_nav-----------------------------------------)

Get app

[Write](https://medium.com/m/signin?operation=register&redirect=https%3A%2F%2Fmedium.com%2Fnew-story&source=---top_nav_layout_nav-----------------------new_post_topnav------------------)

[Search](https://medium.com/search?source=post_page---top_nav_layout_nav-----------------------------------------)

Sign up

[Sign in](https://medium.com/m/signin?operation=login&redirect=https%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c&source=post_page---top_nav_layout_nav-----------------------global_nav------------------)

![Image 3: Unknown user](https://miro.medium.com/v2/resize:fill:64:64/1*dmbNkD5D-u45r44go_cf0g.png)

Member-only story

# The Rails LLM Stack Is Finally Ready for Production. Here Is What I Learned Shipping It.

## Why RubyLLM Finally Changes the Rails Equation

[![Image 4: Raza Hussain](https://miro.medium.com/v2/resize:fill:64:64/1*nN8vMCTUQjzYBoo-iXuDwg.png)](https://mrrazahussain.medium.com/?source=post_page---byline--ff9d20298c5c---------------------------------------)

[Raza Hussain](https://mrrazahussain.medium.com/?source=post_page---byline--ff9d20298c5c---------------------------------------)

Follow

8 min read

·

6 hours ago

[](https://medium.com/m/signin?actionUrl=https%3A%2F%2Fmedium.com%2F_%2Fvote%2Fp%2Fff9d20298c5c&operation=register&redirect=https%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c&user=Raza+Hussain&userId=70f28ee28047&source=---header_actions--ff9d20298c5c---------------------clap_footer------------------)

149

[](https://medium.com/m/signin?actionUrl=https%3A%2F%2Fmedium.com%2F_%2Fbookmark%2Fp%2Fff9d20298c5c&operation=register&redirect=https%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c&source=---header_actions--ff9d20298c5c---------------------bookmark_footer------------------)

[Listen](https://medium.com/m/signin?actionUrl=https%3A%2F%2Fmedium.com%2Fplans%3Fdimension%3Dpost_audio_button%26postId%3Dff9d20298c5c&operation=register&redirect=https%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c&source=---header_actions--ff9d20298c5c---------------------post_audio_button------------------)

Share

Press enter or click to view image in full size

![Image 5](https://miro.medium.com/v2/resize:fit:700/1*0l_-bfm849N4Q59uVtVSoQ.png)

RubyLLM Turbo Streams buffering caused an 8–12s delay in Rails. Disabling nginx and CDN buffering restored progressive streaming.

_RubyLLM in production: streaming failures, token budgets, provider fallback, and what the tutorials skip_

**_This is the Updated version. Every code example below has been verified against the official RubyLLM documentation._**

Python teams have been shipping LLM features for two years while Rails developers duct-taped together hand-rolled HTTP clients or bent Langchain.rb into shapes it was never designed for. The gap was real.

RubyLLM closes most of it. But the README covers the happy path. This covers what the happy path leaves out — the configuration, failure modes, and architectural decisions you need to make before putting real users on it.

RubyLLM is a Ruby gem that wraps multiple LLM providers behind a unified interface. One configuration, multiple backends. OpenAI, Anthropic, Google Gemini, and others sit behind the same API surface.

The pitch sounds like every other abstraction layer. The difference is that RubyLLM was designed from the start to fit Rails conventions rather than fighting them. ActiveRecord integration for chat persistence via `acts_as_chat`. Streaming that plays well with…

## Create an account to read the full story.

The author made this story available to Medium members only.

If you’re new to Medium, create a new account to read this story on us.

[Continue in app](https://play.google.com/store/apps/details?id=com.medium.reader&referrer=utm_source%3Dregwall&source=-----ff9d20298c5c---------------------post_regwall------------------)

Or, continue in mobile web

[Sign up with Google](https://medium.com/m/connect/google?state=google-%7Chttps%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c%3Fsource%3D-----ff9d20298c5c---------------------post_regwall------------------%26skipOnboarding%3D1%7Cregister%7Cremember_me&source=-----ff9d20298c5c---------------------post_regwall------------------)

[Sign up with Facebook](https://medium.com/m/connect/facebook?state=facebook-%7Chttps%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c%3Fsource%3D-----ff9d20298c5c---------------------post_regwall------------------%26skipOnboarding%3D1%7Cregister%7Cremember_me&source=-----ff9d20298c5c---------------------post_regwall------------------)

Sign up with email

Already have an account? [Sign in](https://medium.com/m/signin?operation=login&redirect=https%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c&source=-----ff9d20298c5c---------------------post_regwall------------------)

[](https://medium.com/m/signin?actionUrl=https%3A%2F%2Fmedium.com%2F_%2Fvote%2Fp%2Fff9d20298c5c&operation=register&redirect=https%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c&user=Raza+Hussain&userId=70f28ee28047&source=---footer_actions--ff9d20298c5c---------------------clap_footer------------------)

149

[](https://medium.com/m/signin?actionUrl=https%3A%2F%2Fmedium.com%2F_%2Fvote%2Fp%2Fff9d20298c5c&operation=register&redirect=https%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c&user=Raza+Hussain&userId=70f28ee28047&source=---footer_actions--ff9d20298c5c---------------------clap_footer------------------)

149

[](https://medium.com/m/signin?actionUrl=https%3A%2F%2Fmedium.com%2F_%2Fbookmark%2Fp%2Fff9d20298c5c&operation=register&redirect=https%3A%2F%2Fgenerativeai.pub%2Fthe-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c&source=---footer_actions--ff9d20298c5c---------------------bookmark_footer------------------)

[![Image 6: Raza Hussain](https://miro.medium.com/v2/resize:fill:96:96/1*nN8vMCTUQjzYBoo-iXuDwg.png)](https://mrrazahussain.medium.com/?source=post_page---post_author_info--ff9d20298c5c---------------------------------------)

[![Image 7: Raza Hussain](https://miro.medium.com/v2/resize:fill:128:128/1*nN8vMCTUQjzYBoo-iXuDwg.png)](https://mrrazahussain.medium.com/?source=post_page---post_author_info--ff9d20298c5c---------------------------------------)

Follow

## [Written by Raza Hussain](https://mrrazahussain.medium.com/?source=post_page---post_author_info--ff9d20298c5c---------------------------------------)

[170 followers](https://mrrazahussain.medium.com/followers?source=post_page---post_author_info--ff9d20298c5c---------------------------------------)

·[75 following](https://medium.com/@mrrazahussain/following?source=post_page---post_author_info--ff9d20298c5c---------------------------------------)

Senior Ruby on Rails Engineer | $100K+ Upwork | Sharing Real Experiences | Building a free tool for Ruby on Rails developers | [https://sqltoactiverecord.com](https://sqltoactiverecord.com/)

Follow

[Help](https://help.medium.com/hc/en-us?source=post_page-----ff9d20298c5c---------------------------------------)

[Status](https://status.medium.com/?source=post_page-----ff9d20298c5c---------------------------------------)

[About](https://medium.com/about?autoplay=1&source=post_page-----ff9d20298c5c---------------------------------------)

[Careers](https://medium.com/jobs-at-medium/work-at-medium-959d1a85284e?source=post_page-----ff9d20298c5c---------------------------------------)

[Press](mailto:pressinquiries@medium.com)

[Blog](https://blog.medium.com/?source=post_page-----ff9d20298c5c---------------------------------------)

[Privacy](https://policy.medium.com/medium-privacy-policy-f03bf92035c9?source=post_page-----ff9d20298c5c---------------------------------------)

[Rules](https://policy.medium.com/medium-rules-30e5502c4eb4?source=post_page-----ff9d20298c5c---------------------------------------)

[Terms](https://policy.medium.com/medium-terms-of-service-9db0094a1e0f?source=post_page-----ff9d20298c5c---------------------------------------)

[Text to speech](https://speechify.com/medium?source=post_page-----ff9d20298c5c---------------------------------------)
