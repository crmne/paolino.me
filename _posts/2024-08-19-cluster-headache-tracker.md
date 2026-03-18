---
layout:     post
title:      "Building Cluster Headache Tracker from a Hospital Bed"
date:       2024-08-19 09:00:00
description:    "Cluster headaches hit up to eight times a day. The hospital gave me a paper form with one line per day. So I built an app between attacks."
tags:       [Cluster Headaches, Open Source, Health]
image:      /images/charite_headache_log.jpg
sendfox_campaign_id: 2750873
---
Cluster headaches are called "suicide headaches" for a reason. The worst pain you can imagine, behind one eye, up to eight times a day. I've had them for years.

During my last bout I spent two weeks in hospital. They handed me a paper form, one line per day. One line. For up to eight attacks, each with different intensity, duration, location, and medication. I looked at the form, looked at the nurses, and started coding.

That's how [Cluster Headache Tracker][cht] happened. Built between attacks, in a hospital bed, while I was also supposed to be running [Freshflow][freshflow].

## The app

It started simple: log an attack, note the pain level, track what you took for it. The kind of thing that should have existed already. The headache apps out there are built for migraines. Different condition, different needs. Cluster headaches have their own patterns, their own triggers, their own treatments. Nobody had built something specific.

So I did, and I open-sourced it. People started using it. Some told me it made their doctor visits actually productive for the first time. They could show real data instead of trying to remember through the fog. A few said it helped them get oxygen therapy approved, which can be a fight.

Here's a demo:

<p>
  <iframe
    src="https://www.youtube.com/embed/4HlsqANZdv8?cc_load_policy=1&cc_lang_pref=en"
    title="Cluster Headache Tracker Demo"
    frameborder="0"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
    allowfullscreen>
  </iframe>
</p>

If you get cluster headaches, [try it][cht]. If you're a developer who wants to help, it's on [GitHub][github].

[freshflow]: https://freshflow.ai
[cht]: https://clusterheadachetracker.com
[github]: https://github.com/crmne/cluster-headache-tracker
