# Project artwork

Existing project artwork used on `/projects/`. Raster assets are resized to at
most 800 pixels wide and encoded as WebP (quality 82, metadata stripped). SVG
logos are copied unchanged. Layout, padding, and image fitting are handled by CSS.

All project frames share a 16:9 aspect ratio. Screenshots and portraits fill the
frame with `object-fit: cover`; logos use `contain` with consistent padding so
the complete mark stays visible. An optional `image.position` in `_config.yml`
sets the crop's focal point (for example, `center top` keeps an app's title bar).
Use `image.background` to match a logo's solid background to its frame.

| Asset | Source |
| --- | --- |
| RubyLLM | `ruby_llm/docs/assets/images/logotype.svg` in [RubyLLM](https://github.com/crmne/ruby_llm) |
| ArchSpec | This site's `images/archspec-check.png` |
| Schematist | This site's `images/schematist.png` |
| hyprmoncfg | This site's `images/hyprmoncfg-layout.png` |
| Kamal Backup | `docs/assets/images/logo.svg` in [Kamal Backup](https://github.com/crmne/kamal-backup) |
| Jekyll VitePress | This site's `images/jekyll-vitepress.png` |
| native-packages | `docs/assets/images/logo.svg` in [native-packages](https://github.com/crmne/native-packages) |
| Chat with Work | Marketing screenshot `app/assets/images/screenshot-1-light.webp` from Chat with Work |
| Spotifast | `docs/screenshot.png` in [Spotifast](https://github.com/crmne/spotifast) |
| ZapFast | `docs/screenshot.png` in [ZapFast](https://github.com/crmne/zapfast) |
| TonePush | `docs/screenshot.png` in [TonePush](https://github.com/crmne/tonepush) |
| RekordFlash | The app's existing `packaging/macos/icon-1024.png` |
| Cluster Headache Tracker | `app/assets/images/logo.png` in [Cluster Headache Tracker](https://github.com/crmne/cluster-headache-tracker) |
| OmaStats | `preview.png` in [OmaStats](https://github.com/crmne/omastats) |
| OmaTasks for Todoist | `preview.png` in [OmaTasks for Todoist](https://github.com/crmne/omatasks) |
| Ultimate Guitar Tabs | `preview.png` in [Ultimate Guitar Tabs](https://github.com/crmne/omarchy-ultimate-guitar) |
| Lyrics Synced with Music | `preview.png` in [Lyrics Synced with Music](https://github.com/crmne/omarchy-lyrics) |
| hyprmoncfg for Omarchy | `preview.png` in [hyprmoncfg for Omarchy](https://github.com/crmne/omarchy-hyprmoncfg) |
| Active Window + Icon | `preview.png` in [Active Window + Icon](https://github.com/crmne/omarchy-active-window) |
| Media Controls + Album Art | `preview.png` in [Media Controls + Album Art](https://github.com/crmne/omarchy-mpris) |
| Berlin.rb | `assets/logo.svg` in [Berlin.rb](https://github.com/crmne/berlinrb.org) |
| Crimson Lake | Public artist image from [Floppy Disco](https://floppydisco.live/artists/crimson-lake) |
| Floppy Disco | Public social-preview logo from [Floppy Disco](https://floppydisco.live) |
| Mindscape | Public social-preview logo from [Mindscape](https://enterthemindscape.org) |
