---
layout: post
title: "Dictation Is the New Prompt (Voxtype on Omarchy)"
date: 2026-01-07
description: "Stop typing every prompt. Speak it instead, with a fast Rust stack and a clean Omarchy setup."
tags: [AI, Voice, Linux, Omarchy, Rust, Productivity]
image: /images/omarchy-voxtype-demo.png
video: /images/omarchy-voxtype-demo.mp4
---

Typing every prompt with your fingers feels backwards in 2026. We can speak faster than we can type, and it feels more natural. Hold a hotkey, speak, and your OS types it for you. If you care about flow, dictation is the most underrated AI upgrade you can make.

In the [Omarchy](https://omarchy.org/) world, [Hyprwhspr](https://github.com/goodroot/hyprwhspr) is getting a lot of attention after a recent DHH tweet:

{% twitter https://twitter.com/dhh/status/2007498242561593535 %}

He's right: local dictation is _shockingly_ good now. The catch is Hyprwhspr uses Python virtual environments, which don't mix well with [mise](http://mise.jdx.dev/). Fortunately [Pete Jackson](https://github.com/peteonrails) [saw that and created](https://github.com/basecamp/omarchy/discussions/3872) [Voxtype](https://github.com/peteonrails/voxtype/) to solve exactly this issue!

## Why Voxtype

Voxtype is built in Rust, so you don't need Python virtual environments which means it works well with mise. It's fast, it just works, and when [I opened an issue asking for an Omarchy theme](https://github.com/peteonrails/voxtype/issues/26), [the author shipped it immediately](https://github.com/peteonrails/voxtype/releases/tag/v0.4.4). Now it looks *stunning* in my setup.

With Vulkan enabled, transcription is almost instant on my Ryzen AI 9 HX370. The video at the top is not sped up. Longer text also transcribes instantly.

If you want to copy my exact configuration, here it is.

## Install

```bash
sudo pacman -S wtype ydotool wl-clipboard vulkan-icd-loader # last only if you want to use your GPU
sudo yay -S voxtype

voxtype setup --download
voxtype setup gpu # if you want to use your GPU
voxtype setup systemd
```

Restart Waybar after the changes:

```bash
pkill -SIGUSR2 waybar
```

## Voxtype config

`~/.config/voxtype/config.toml`

```toml
state_file = "auto"

[hotkey]
enabled = false

[audio]
device = "default"
sample_rate = 16000
max_duration_secs = 600

[audio.feedback]
enabled = true
# Sound theme: "default", "subtle", "mechanical", or path to custom theme directory
theme = "default"
volume = 0.7

[whisper]
model = "base.en"
language = "en"
translate = false
on_demand_loading = true # saves your GPU until it's needed

[output]
mode = "type"
fallback_to_clipboard = true

# Delay between typed characters in milliseconds
# 0 = fastest possible, increase if characters are dropped
type_delay_ms = 1

[output.notification]
on_recording_start = false
on_recording_stop = false
on_transcription = true

[text]
replacements = { "hyperwhisper" = "hyprwhspr" }

[status]
icon_theme = "omarchy"
```

## Waybar integration

`~/.config/waybar/config.jsonc`

```jsonc
"custom/voxtype": {
  "exec": "voxtype status --follow --format json",
  "return-type": "json",
  "format": "{}",
  "tooltip": true
},
```

And add it to `modules-right`:

```jsonc
"modules-right": [
  "group/tray-expander",
  "custom/voxtype",
  "bluetooth",
  "network",
  "pulseaudio",
  "cpu",
  "battery"
]
```

`~/.config/waybar/style.css`

```css
@import "voxtype.css";
@import "../omarchy/current/theme/waybar.css";
```

`~/.config/waybar/voxtype.css`

```css
#custom-voxtype {
  margin: 0 16px 0 0;
  font-size: 12px;
  font-weight: bold;
  border-top: 2px solid transparent;
  border-bottom: 2px solid transparent;
  transition: color 150ms ease-in-out, border-color 150ms ease-in-out;
}

#custom-voxtype.recording {
  color: #ff5555;
  animation: pulse 1s ease-in-out infinite;
}

#custom-voxtype.transcribing {
  color: #ff5555;
}

#custom-voxtype.stopped {
  color: #6272a4;
}

@keyframes pulse {
  0% { opacity: 1; }
  50% { opacity: 0.5; }
  100% { opacity: 1; }
}
```

## Keybinding

In your Hyprland config:

```ini
# Voxtype
bindd = SUPER, XF86AudioMicMute, Transcribe, exec, voxtype record start
bindr = SUPER, XF86AudioMicMute, exec, voxtype record stop
```

That's it. Use your voice whenever possible. It's faster, it's more natural, and it keeps you in flow. This is what prompting in 2026 should feel like.
