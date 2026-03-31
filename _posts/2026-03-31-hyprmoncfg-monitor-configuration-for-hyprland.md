---
layout: post
title: "I Built a Monitor Configuration Tool for Hyprland"
date: 2026-03-31
description: "A spatial TUI editor with drag-and-drop, safe apply with revert, workspace planning, and a hotplug daemon. All in two zero-dependency Go binaries."
tags: [Hyprland, Open Source, Go, Linux, TUI]
image: /images/hyprmoncfg-demo.gif
sendfox_campaign_id: 2764102
---
Configuring monitors in Hyprland means writing `monitor=` lines by hand. A 4K display at 1.33x scale is effectively 2880x1620 pixels, so the monitor next to it needs to start at x=2880. Vertically centering a 1080p panel against it means doing division in your head to get the y-offset right. You reload, you're off by 40 pixels, you edit, you reload again. There's no visual feedback until after you've committed to a config.

Then it gets worse. You unplug your laptop, go to a conference, plug into a projector, and you're back to editing config files backstage before your talk. You come home, dock the laptop, and the layout is wrong again.

I looked at what was available. The closest to what I wanted was [Monique](https://github.com/ToRvaLDz/monique): spatial editor, profiles, workspace management, a hotplug daemon. It does exactly what I need. But it's a GTK4 GUI that pulls in Python and a stack of dependencies, and the daemon was broken when I tried it. The other tools each cover parts of this: [kanshi](https://sr.ht/~emersion/kanshi/) does profiles and auto-switching but has no editor, you write config files; [nwg-displays](https://github.com/nwg-piotr/nwg-displays) and [HyprMon](https://github.com/erans/hyprmon) have spatial editors but no daemon; [HyprDynamicMonitors](https://github.com/fiffeek/hyprdynamicmonitors) has a daemon but no real layout tool, and it pulls in UPower and D-Bus.

I wanted Monique's feature set without the dependency baggage, in something that works over SSH when your monitors are broken. So I built [hyprmoncfg](https://hyprmoncfg.dev).

## A real spatial editor, in your terminal

The TUI is the thing I'm most proud of. It's not a config editor with a preview pane. It's a full spatial layout tool.

The left side is a canvas where your monitors are drawn as rectangles, proportional to their resolution. You click one to select it, drag it to move it. Monitors snap to each other's edges as you position them, just like arranging windows in a GUI display manager. Arrow keys give you fine control: 100px per step, Shift for 10px, Ctrl for 1px.

The right side is a per-monitor inspector. Pick a resolution and refresh rate from a scrollable list. Set scale, position, transform, VRR, mirroring. All inline, no dialogs within dialogs. A third tab handles workspace planning.

And because it's a TUI: it works over SSH. When your monitor configuration is broken and you can't see anything, you can SSH into the machine and fix it. Try that with a GTK app.

## Safe apply with automatic revert

Every apply, whether from the TUI or the daemon, follows the same path: write `monitors.conf` atomically (temp file + rename, no corruption), reload Hyprland, re-read the actual monitor state, and verify the result matches what was requested.

Then it gives you 10 seconds to confirm. If you don't, maybe because the layout left you staring at a black screen, it reverts automatically. No stuck monitors. No reaching for a second machine to undo the damage.

This is the same apply engine everywhere. The TUI and the daemon share identical code. If it works when you test it interactively, it works when the daemon fires at 2am because you bumped your dock cable.

## Workspace planning

Monitor configuration and workspace assignment are the same problem. If you're rearranging monitors, you probably want workspaces to follow. hyprmoncfg has a workspace planner built into its third tab, with three strategies:

- **Sequential**: Groups in chunks. Workspaces 1-3 on monitor A, 4-6 on monitor B.
- **Interleave**: Round-robins. 1→A, 2→B, 3→A, 4→B.
- **Manual**: Explicit per-workspace rules when you want full control.

Workspace assignments are stored inside each profile and applied together with the layout. Switch profiles, switch workspace distribution. One operation.

## Source-chain verification

Here's something no other tool does. Before writing anything, hyprmoncfg parses your `hyprland.conf` and verifies it actually sources the target `monitors.conf`. If it doesn't, it refuses to write.

Other tools skip this check. They silently update a file that Hyprland never reads. You spend twenty minutes debugging why nothing changed, only to realize the file was never sourced. I lost an evening to this once. Never again.

## Dotfiles integration

Profiles are stored as JSON files in `~/.config/hyprmoncfg/profiles/`, one per profile. The generated `monitors.conf` is a build artifact, you don't commit it. You commit the profiles.

```sh
chezmoi add ~/.config/hyprmoncfg
```

Save a "desk" profile at home with your ultrawide. Save "conference-1080p" at one venue. Save "conference-4k" at another. Sync them across machines via your [dotfiles](https://github.com/crmne/dotfiles). The daemon matches profiles to connected hardware automatically. Arrive somewhere, plug in, and the right layout applies.

This is portable. The same profile library works across machines because matching is based on the monitors you have, not on the machine you're at.

## One runtime dependency: Hyprland

Two compiled Go binaries. No Python, no GTK, no GObject introspection, no D-Bus, no UPower. Install them and you're done. The only runtime requirement is Hyprland itself.

## How it compares

| | hyprmoncfg | Monique | HyprDynamicMonitors | HyprMon | nwg-displays | kanshi |
|---|---|---|---|---|---|---|
| Spatial layout editor | Yes | Yes (GTK4) | Partial (TUI) | Yes | Yes (GTK3) | No |
| Drag-and-drop | Yes | Yes | No | Yes | Yes | No |
| Snapping | Yes | Not documented | No | Yes | Yes | No |
| Profiles | Yes | Yes | Yes | Yes | No | Yes |
| Auto-switching daemon | Yes | Yes | Yes | No (roadmap) | No | Yes |
| Workspace planning | Yes | Yes | No | No | Basic | No |
| Safe apply with revert | Yes | Yes | No | Partial (manual rollback) | No | No |
| Source-chain verification | Yes | No | No | No | No | No |
| Works over SSH | Yes | No | No | No | No | N/A |
| Additional runtime dependencies | None | Python + GTK4 + libadwaita | UPower, D-Bus | None | Python + GTK3 | None |

## Try it

On Arch:

```sh
yay -S hyprmoncfg
```

Or build from source:

```sh
go install github.com/crmne/hyprmoncfg/cmd/hyprmoncfg@latest
go install github.com/crmne/hyprmoncfg/cmd/hyprmoncfgd@latest
```

Check out the [documentation](https://hyprmoncfg.dev/) for the full guide, or browse the [source on GitHub](https://github.com/crmne/hyprmoncfg).
