---
layout: post
title: "Solco: Stop Preparing Your Tracks, Start Preparing Your Gigs"
seo_title: "Solco private beta: a DJ library app that writes your CDJ USB"
date: 2026-10-28 15:30:00 +0100
description: "Solco grids, keys and characterises your whole DJ library on your computer and writes the USB your CDJs read. It's in private beta: join the waitlist for a personal licence key."
tags: [Solco, DJing, AI, Rust]
image: /images/solco.jpg
video: https://getsolco.com/media/solco-launch.mp4
---

Some of you may not know this, but I'm a DJ in my free time. I founded [Floppy Disco](https://floppydisco.live), a music collective to bring the magic of Disco and House to Berlin, and I've played clubs all over here and in other places in Europe. I love DJing, and my favourite part is finding new music and playing it for people.

Preparing my tracks, however, has never been truly fun. It rather felt like admin: fixing beat grids that were often wrong, fighting clunky software like rekordbox, building playlists by hand, correcting tags and genres, updating playlists, and deciding whether ratings or colours should stand for energy, mood or vocals.

So I said _enough_, and built [Solco](https://getsolco.com) to do that work for me. Today it opens as a private beta.

## What it does

You drop your music in. Solco grids every track, finds its key and loudness, hears its genre and character (energy, drive, dance, vocals and more, each from 0 to 100), fixes its tags and finds your duplicates by their sound. Then it writes the USB drive your Pioneer CDJs and XDJs read. No rekordbox needed, and no laptop in the booth. It also imports from rekordbox, Traktor and Apple Music, and exports Traktor collections and M3U8 playlists.

Everything is analysed on your computer, by a dozen AI models, each built for its own job. Your music never leaves your computer.

There's also an assistant. Describe the night ("four hours of disco from 10pm, funky openers building to peak disco") and it proposes a folder of playlists from your own library, in playing order, which you review before it creates anything. Or name a playlist you already have and ask it to build more slowly, or cut it to 90 minutes. It shows you every track it would add, move and remove, and changes nothing until you say so.

## The numbers

Don't take my word for it. Here's Solco against rekordbox 7:

- **The USB stick.** I timed both apps putting the same 493 tracks on the same USB stick for the first time. Solco took **12 minutes**. rekordbox took **three and a half hours**. (Mac mini M4, 250 GB SanDisk stick on FAT32, rekordbox 7.2.6, median of three runs.)
- **Beat grids.** Downbeats: 38% better. Beats: 12% better. That's Solco against rekordbox 7 on the 998 excerpts of [GTZAN](https://github.com/TempoBeatDownbeat/gtzan_tempo_beat), ten genres that researchers annotated by hand. [How we measured](https://getsolco.com/measured.html).

## A private beta, with a key for each person

Solco works with a licence key made for you. I'm letting DJs in from the waitlist in small groups, so I can answer every message and fix what breaks before the next group comes in.

How the keys work:

- **Join the waitlist** at [getsolco.com](https://getsolco.com). When there's a seat for you, your key comes by email. Each friend you refer moves you up 5 places.
- **Activate it once.** Paste the key into Solco's first screen. Activating needs the internet once, and then Solco works offline.
- **Up to three computers.** Your key is yours alone and works on up to three of your computers.
- **It renews itself.** While the beta lasts, your key renews by itself, and new builds with fixes come out often.

The private beta is free. It runs on macOS (Apple Silicon), Windows and Linux.

It's a beta, so keep a backup of your music and use a spare USB stick for your first exports. And tell me what works, what doesn't and what you wish it did: there's a Feedback button right in the app, and I read everything at hello@getsolco.com.

Stop preparing your tracks. Start preparing your gigs.

**[Join the private beta](https://getsolco.com)**
