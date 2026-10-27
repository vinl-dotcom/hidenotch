<div align="center">

[![English](https://img.shields.io/badge/README-English-2563eb?style=for-the-badge)](README.md)
[![中文](https://img.shields.io/badge/README-中文-lightgrey?style=for-the-badge)](README.zh-CN.md)

![Version](https://img.shields.io/badge/version-1.1-2ea44f?style=for-the-badge)
![Platform](https://img.shields.io/badge/macOS-12%2B-555?style=for-the-badge&logo=apple)

</div>

# HideNotch — Hide the MacBook Notch

Licensed under the GNU General Public License v3.0 only. See [LICENSE](LICENSE).

Paints the strip behind the built-in display's menu bar black. The translucent menu bar samples
that black and turns fully black, so the physical notch (itself black) blends in and visually
disappears — while the rest of your desktop stays light. Keep Light Mode during the day without
switching to Dark.

Unlike many similar tools, this is a lightweight background agent that watches for
**wallpaper changes / Space switches / display hot-plug / wake from sleep** and **re-applies the
black strip automatically** — exactly why those other tools tend to "stop working."

## Install

```bash
bash build.sh          # compile + bundle + install to ~/Applications/HideNotch.app
bash install-agent.sh  # enable launch-at-login (LaunchAgent) and start now
```

No system permissions required (no Accessibility / Screen Recording), no sudo.

## Uninstall

```bash
bash uninstall.sh
```

Stops the process, restores your original wallpaper, removes all files.

## How it works

1. Find the built-in notched display (`safeAreaInsets.top > 0`).
2. Read the current wallpaper, generate a native-resolution image = original scaled to fill +
   a pure-black bar of menu-bar height at the top.
3. Set it as that display's wallpaper via `NSWorkspace.setDesktopImageURL`.
4. Watch the relevant events and regenerate whenever the wallpaper changes (plus a 5-second
   fallback poll).

### External display protection (triple defense)

macOS syncs wallpapers across displays by default, which would push the patched wallpaper
(with its black bar) to external monitors. HideNotch prevents this with three layers:

1. **Disable sync**: writes `com.apple.wallpaper StretchyCropping` to `false` via `defaults`.
2. **Capture & restore**: before patching the built-in display, saves each external monitor's
   original wallpaper URL; after patching, restores them immediately + again at 1 s and 3 s
   delays to cover async sync.
3. **Clean fallback**: if an external monitor has already been synced to the patched wallpaper,
   generates a clean version (same image, no black bar) at the correct resolution and applies it.

The generated patch image, clean image, and the original wallpaper path are stored in
`~/Library/Application Support/HideNotch/`.

## Limitations

- **Relies on menu-bar translucency**: if *System Settings > Accessibility > Display > Reduce
  transparency* is on, the menu bar becomes opaque and no longer samples what's behind it, so the
  black strip won't show. (Every comparable approach shares this limit.)
- **Static image wallpapers only**: with dynamic / Aerial / photo-shuffle wallpapers the system
  can't return a single image, so the tool skips and leaves your wallpaper untouched. Best paired
  with a fixed static light wallpaper.
- **External displays**: the built-in display gets the patched wallpaper; external monitors are
  actively restored to their original wallpapers (see triple defense above). If you use wallpaper
  sync intentionally, disable it in System Settings for best results.

## Design tradeoffs

**Why it works even when you can't see the desktop.** The black strip lives behind the
**always-visible** menu bar — it's not about looking at the desktop. Normal windows (even
maximized) sit *below* the menu bar and never go behind it, so the area behind the menu bar is
always the wallpaper's black strip → as long as the menu bar is visible, the notch stays hidden,
regardless of whether you're looking at the desktop. The only exception is true full-screen, where
the menu bar auto-hides and the notch goes with it.

**Why wallpaper patching, not an overlay window.** An overlay-window approach (a black window
covering the menu bar) was prototyped but has a fundamental problem: the window must sit at the
same level as the menu bar (`.statusBar`), which covers the menu-bar text and makes it invisible.
Placing it below the menu bar doesn't work either — the translucent menu bar samples the
wallpaper, not windows beneath it. Wallpaper patching avoids this entirely because the black lives
*inside* what the menu bar samples. The tradeoff is static wallpapers only; if you use dynamic
wallpapers, this tool won't help.

**How it compares.**
- *Resolution-switching tools (znotch / BetterDisplay)*: switch to a slightly shorter "notchless"
  resolution — bulletproof and independent of transparency, but **sacrifices vertical screen
  space**, and non-native scaling can look slightly blurry.
- *This tool (black wallpaper strip)*: **loses no screen space, stays pixel-sharp**, at the cost
  of relying on menu-bar translucency and only fitting static wallpapers.
