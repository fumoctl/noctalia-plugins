# noctalia-plugins

Personal [Noctalia](https://github.com/noctalia-dev/noctalia) plugin source repository.

## Plugins

- [`fumoctl/portal-screen-mirror`](portal-screen-mirror/README.md) — Mirror any screen, individual window, or rectangular region onto another display via XDG `ScreenCast` (or `zwlr_screencopy_manager_v1` for regions) and a click-through `zwlr-layer-shell-v1` overlay surface.

## Compatibility (`fumoctl/portal-screen-mirror`)

`fumoctl/portal-screen-mirror` is compositor-agnostic across Wayland desktops where Noctalia runs, with zero compositor-specific CLI or IPC calls:

| Component | Protocol / API Used | Compositor Support |
| :--- | :--- | :--- |
| **Output discovery & UI** | `noctalia.outputs()` (`wl_output` + `xdg-output`) | Any compositor running Noctalia |
| **Mirror display surface** | `zwlr-layer-shell-v1` (`[[layer]]` + `ui.pixelStream`) | Any layer-shell compositor (Umbriel, Hyprland, Niri, Sway, MangoWC, Labwc, River, KDE KWin — i.e., everywhere Noctalia runs; GNOME Mutter lacks `zwlr-layer-shell-v1`) |
| **Portal Picker mode** | `org.freedesktop.portal.ScreenCast` (`types = 3`) + PipeWire SHM (`MemFd`) | **Full screen + individual windows** on Umbriel (`xdg-desktop-portal-umbriel`), Hyprland (`xdg-desktop-portal-hyprland`), Niri (`xdg-desktop-portal-gnome`), and KDE (`xdg-desktop-portal-kde`). **Full screen only** on Sway, Labwc, and River using `xdg-desktop-portal-wlr` (since `xdg-desktop-portal-wlr` implements monitor capture only, not per-window capture). |
| **Rectangular Region mode** | `slurp` + `zwlr_screencopy_manager_v1`, with automatic `ScreenCast` + `videocrop` fallback | **Instant (no portal prompt)** on compositors implementing `wlr-screencopy` (Umbriel, Hyprland, Niri, Sway, River, Labwc, MangoWC). **Automatic portal fallback** (prompts once per monitor and caches `restore_token`) on compositors without `wlr-screencopy` (such as KDE KWin). |

- **No compositor window rules required**: Frames render into a plugin-owned `zwlr-layer-shell-v1` `overlay` surface bound directly to the target connector (`noctalia.layer.configure`), avoiding `xdg_toplevel.set_fullscreen` output-placement quirks.
- **PipeWire pixel formats**: Negotiates `{BGRx, BGRA, RGBx, RGBA}` system-memory (`MemFd`) buffers, supported by every major `ScreenCast` portal backend (`-umbriel`, `-hyprland`, `-wlr`, `-gnome`, `-kde`).

## Using as a Noctalia Git Source

Ensure runtime dependencies (`python3` with `PyGObject`, GStreamer `base`/`good`/`pipewire` plugins, `slurp`, `pipewire`, and an `xdg-desktop-portal` `ScreenCast` backend) are installed, then add the source:

```sh
noctalia msg plugins source add fumoctl git https://github.com/fumoctl/noctalia-plugins
noctalia msg plugins enable fumoctl/portal-screen-mirror
```

## Opening a PR to `noctalia-dev/community-plugins`

1. Fork and clone `https://github.com/noctalia-dev/community-plugins`, then create a branch.
2. Copy `portal-screen-mirror/` into the root of that checkout (`cp -r portal-screen-mirror /path/to/community-plugins/`).
   - Do **not** copy `catalog.toml` — `community-plugins` regenerates its `catalog.toml` automatically in CI.
   - Optionally replace `portal-screen-mirror/thumbnail.webp` with a live screenshot exported via [thumbnail-generator.html](https://assets.noctalia.dev/plugins/thumbnail-generator.html) (`960x540` WebP).
3. Commit and open a PR against `noctalia-dev/community-plugins:main`.
