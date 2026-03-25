---
layout: post
title: "I Built a Monitor Configuration Tool for Hyprland"
date: 2026-03-31
description: "Configuring monitors in Hyprland means editing config files by hand, guessing at coordinates, and watching your layout break every time a connector swaps. So I built hyprmoncfg."
tags: [Hyprland, Open Source, Go, Linux, TUI]
image: /images/hyprmoncfg-layout.png
---

Configuring monitors in Hyprland means writing `monitor=` lines by hand. You guess at coordinates, reload, realize they're wrong, edit again. There's no visual feedback until after you've committed to a config.

Then it gets worse. You unplug your laptop, go to a conference, plug into a projector -- and you're back to editing config files backstage before your talk. You come home, dock the laptop, and the layout is wrong again because `DP-1` and `DP-2` swapped since last boot.

I got tired of this. So I built [hyprmoncfg](https://github.com/crmne/hyprmoncfg).

## What it is

Two binaries. `hyprmoncfg` is an interactive TUI for layout editing, profile management, and workspace planning. `hyprmoncfgd` is a background daemon that auto-applies profiles when you plug in or unplug a monitor. Both are compiled Go, zero runtime dependencies, and they use the exact same apply engine -- no "best effort" daemon behavior, no silent failures.

The TUI isn't a glorified config editor. It's a real spatial tool: drag-and-drop layout canvas on the left, per-monitor inspector on the right. Pick resolutions, set scales, adjust positions with pixel-level precision. All in your terminal. It even works over SSH.

## Why profiles need to follow hardware, not ports

This is the thing that drove me crazy enough to build a tool. Hyprland identifies monitors by connector name: `DP-1`, `DP-2`, `HDMI-A-1`. These names are assigned at boot based on detection order. Unplug your dock, replug it, and suddenly your left monitor is `DP-2` and your right one is `DP-1`. Your carefully assigned workspaces are now backwards.

hyprmoncfg profiles store monitor identity by make, model, and serial number. The connectors can swap all they want. Your layout holds.

Save a "desk" profile at home with your external monitors. Save a "conference-1080p" profile at one venue. Save a "conference-4k" at another. Add them all to your dotfiles. The daemon handles the rest -- arrive at a venue, plug in, and the right profile applies automatically.

## Source-chain verification

Here's something no other tool does: before writing anything, hyprmoncfg checks that your `hyprland.conf` actually sources the target `monitors.conf`. Other tools skip this and silently update files that Hyprland never reads. You spend twenty minutes debugging why nothing changed, only to realize the file was never sourced.

## The workspace problem

Monitor configuration and workspace assignment are the same problem. If you're rearranging monitors, you probably want workspaces to follow. hyprmoncfg has a workspace planner built right in, with three strategies:

- **Sequential**: Groups workspaces in chunks. 1-3 on monitor A, 4-6 on monitor B.
- **Interleave**: Round-robins across monitors. 1→A, 2→B, 3→A.
- **Manual**: Explicit per-workspace rules for when you want full control.

Workspace assignments are stored inside each profile and applied together with the layout.

## How it compares

| | hyprmoncfg | Monique | nwg-displays | kanshi |
|---|---|---|---|---|
| Interface | TUI | GTK4 GUI | GTK3 GUI | Config file |
| Profiles | Yes | Yes | No | Yes |
| Auto-switching daemon | Yes | Yes | No | Yes |
| Workspace management | Yes | Yes | Basic | No |
| Confirm/revert safety | Yes | Yes | No | No |
| Runtime dependencies | None | Python + GTK4 | Python + GTK3 | None |
| Works over SSH | Yes | No | No | N/A |
| Source-chain verification | Yes | No | No | No |

## Try it

```sh
go install github.com/crmne/hyprmoncfg/cmd/hyprmoncfg@latest
go install github.com/crmne/hyprmoncfg/cmd/hyprmoncfgd@latest
```

Or check out the [documentation](https://crmne.github.io/hyprmoncfg/) for other install options and the full guide.
