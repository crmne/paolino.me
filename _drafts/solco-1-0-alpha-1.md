---
layout: post
title: "Solco: Stop Preparing Your Tracks, Start Preparing Your Gigs"
seo_title: "Solco 1.0 alpha 1: a DJ library app that writes your CDJ USB"
date: 2026-10-27 16:00:00 +0100
description: "Solco grids, keys and characterises your whole DJ library on your computer and writes the USB your CDJs read. The 1.0 alpha 1 is a private alpha: join the waitlist for a personal licence key."
tags: [Solco, DJing, AI, Rust]
---
<!-- DRAFT for Carmine. Not published: it lives in _drafts on the solco-1-0-alpha-1 branch.
Before publishing: add the image (images/solco.png from the film's cover or the BetaList shot) and the film video line,
add sendfox_campaign_id if it should go to the newsletter, and move it to _posts with the launch date.
No key accuracy claim: Solco's own key analyser is behind rekordbox 7 on GiantSteps Key. Every number below comes from the launch kit's Sources section (crmne/announcements, products/solco/1.0.0-alpha.1.md). -->

I've been building a DJ app. It's called [Solco](https://getsolco.com), and today I'm opening the waitlist for its first 1.0 alpha.

I built it so I could focus on what I love most: finding new music and playing it for people.

Getting ready for a gig used to feel like admin. Fixing beat grids that were wrong. Building playlists by hand from a library I'd grown for years without much order. Fixing the genre of every single track. Deciding whether ratings or colours should stand for energy, or mood, or vocals.

So I built Solco to do that work for me.

## What it does

You drop your music in. Solco grids every track, finds its key and loudness, hears its genre and character (energy, drive, dance, vocals and more, each from 0 to 100), fixes its tags and finds your duplicates by their sound. Then it writes the USB drive your Pioneer CDJs and XDJs read. No rekordbox needed, and no laptop in the booth.

Everything is analysed on your computer. Your music never leaves it.

There's also an assistant. Describe the night ("four hours of disco from 10pm, funky openers building to peak disco") and it proposes a folder of playlists from your own library, in playing order, which you review before it creates anything. Or name a playlist you already have and ask it to build more slowly, or cut it to 90 minutes. It shows you every track it would add, move and remove, and changes nothing until you say so.

## The numbers

I don't want you to take my word for it, so I measured Solco against rekordbox 7 (7.2.6, Auto mode) on a public music collection that researchers annotated by hand.

- **Beat grids.** On the 998 excerpts of [GTZAN](https://github.com/TempoBeatDownbeat/gtzan_tempo_beat), ten genres with human beat annotations, Solco's grids matched the beats more closely than rekordbox 7's: beat F-measure 0.86 against 0.77. It found the downbeat far more often: 0.74 against 0.53.

What I can't claim: Solco isn't faster than rekordbox. It's slower on the same Mac. On keys, rekordbox is still ahead, and I'm working on it. And these are 30-second excerpts, not a full DJ library. My own library of 9,000-odd tracks is where Solco grew up, and I'm curious what yours will find.

## A private alpha, with a key for each person

Anyone can download Solco 1.0 alpha 1, but it only works with a licence key made for you. I'm letting DJs in in small groups, so I can answer every message and fix what breaks before the next group comes in.

How the keys work:

- **Join the waitlist** at [getsolco.com](https://getsolco.com). When there's a seat for you, your key comes by email.
- **Activate it once.** Paste the key into Solco's first screen. Activating needs the internet once, and then Solco works offline.
- **Up to three computers.** Your key is yours alone and works on up to three of your computers.
- **Builds don't expire.** Your key lasts until the date in your email, and new alphas come out often.

The alpha is free. It runs on macOS (Apple Silicon), Windows and Linux.

It's an alpha, so keep a backup of your music and use a spare USB stick for your first exports. And tell me what works, what doesn't and what you wish it did: there's a Feedback button right in the app, and I read everything at hello@getsolco.com.

Stop preparing your tracks. Start preparing your gigs.

**[Join the waitlist](https://getsolco.com)**
