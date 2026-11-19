# Portal Screen Mirror

Mirror any screen, individual window, or rectangular region onto another display through XDG `ScreenCast` and a click-through `zwlr-layer-shell-v1` overlay surface — no compositor window rules required.

## Plugin

| Field | Value |
| --- | --- |
| ID | `fumoctl/portal-screen-mirror` |
| Entries | Bar widget: `mirror`; panel: `controls`; layer: `display`; service: `mirror-service`; shortcut: `toggle` |

## Compatibility

`fumoctl/portal-screen-mirror` is compositor-agnostic across Wayland desktops where Noctalia runs, with zero compositor-specific CLI or IPC calls.

| Component | Protocol / API Used | Compositor Support |
| :--- | :--- | :--- |
| **Output discovery & UI** | `noctalia.outputs()` (`wl_output` + `xdg-output`) | Any compositor running Noctalia |
| **Mirror display surface** | `zwlr-layer-shell-v1` (`[[layer]]` + `ui.pixelStream`) | Any layer-shell compositor (Umbriel, Hyprland, Niri, Sway, MangoWC, Labwc, River, KDE KWin — i.e., everywhere Noctalia runs; GNOME Mutter lacks `zwlr-layer-shell-v1`) |
| **Portal Picker mode** | `org.freedesktop.portal.ScreenCast` (`types = 3`) + PipeWire SHM (`MemFd`) | **Full screen + individual windows** on Umbriel (`xdg-desktop-portal-umbriel`), Hyprland (`xdg-desktop-portal-hyprland`), Niri (`xdg-desktop-portal-gnome`), and KDE (`xdg-desktop-portal-kde`). **Full screen only** on Sway, Labwc, and River using `xdg-desktop-portal-wlr` (since `xdg-desktop-portal-wlr` implements monitor capture only, not per-window capture). |
| **Rectangular Region mode** | `slurp` + `zwlr_screencopy_manager_v1`, with automatic `ScreenCast` + `videocrop` fallback | **Instant (no portal prompt)** on compositors implementing `wlr-screencopy` (Umbriel, Hyprland, Niri, Sway, River, Labwc, MangoWC). **Automatic portal fallback** (prompts once per monitor and caches `restore_token`) on compositors without `wlr-screencopy` (such as KDE KWin). |

- **No compositor window rules required**: Frames render into a plugin-owned `zwlr-layer-shell-v1` `overlay` surface configured dynamically on the target connector (`noctalia.layer.configure`), so mirroring works reliably even on compositors that ignore `xdg_toplevel.set_fullscreen` target output hints (such as Umbriel).
- **PipeWire pixel formats**: Negotiates `{BGRx, BGRA, RGBx, RGBA}` system-memory (`MemFd`) buffers, which every major `ScreenCast` portal backend (`-umbriel`, `-hyprland`, `-wlr`, `-gnome`, `-kde`) advertises as its standard 8-bit SHM fallback.

## Requirements

- `python3` with `PyGObject` (`gi`) and GStreamer 1.0 (`gstreamer`, `gst-plugins-base`, `gst-plugins-good`, and the PipeWire GStreamer plugin `libgstpipewire`)
- `slurp` on `PATH` for rectangular region selection
- `libwayland-client` (`libwayland-client.so.0`) for native `zwlr_screencopy_manager_v1` region capture
- `xdg-desktop-portal` with an active `org.freedesktop.portal.ScreenCast` backend (such as `xdg-desktop-portal-umbriel`, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-wlr`, `xdg-desktop-portal-gnome`, or `xdg-desktop-portal-kde`) and `pipewire`

### Packages by Distribution

Also install your compositor's `ScreenCast` portal backend (`xdg-desktop-portal-umbriel`, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gnome`, `xdg-desktop-portal-kde`, or `xdg-desktop-portal-wlr`) if it is not already enabled.

**Arch Linux / CachyOS / EndeavourOS**

```sh
sudo pacman -S python python-gobject gstreamer gst-plugins-base gst-plugins-good gst-plugin-pipewire slurp wayland pipewire xdg-desktop-portal
```

**Fedora**

```sh
sudo dnf install python3 python3-gobject gstreamer1 gstreamer1-plugins-base gstreamer1-plugins-good pipewire-gstreamer slurp wayland-libs-client pipewire xdg-desktop-portal
```

**Debian / Ubuntu / Pop!_OS**

```sh
sudo apt install python3 python3-gi gir1.2-gstreamer-1.0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-pipewire slurp libwayland-client0 pipewire xdg-desktop-portal
```

**openSUSE Tumbleweed / Slowroll**

```sh
sudo zypper install python3 python3-gobject typelib-1_0-Gst-1_0 gstreamer gstreamer-plugins-base gstreamer-plugins-good gstreamer-plugin-pipewire slurp libwayland-client0 pipewire xdg-desktop-portal
```

**Void Linux**

```sh
sudo xbps-install -S python3 python3-gobject gstreamer1 gst-plugins-base1 gst-plugins-good1 gstreamer1-pipewire slurp wayland pipewire xdg-desktop-portal
```

**NixOS (Home Manager)**

On NixOS, GObject Introspection typelibs, GStreamer plugins, and `libwayland-client.so.0` live in isolated `/nix/store` paths. Expose them to `noctalia.service` and register the plugin source declaratively in `programs.noctalia.settings` (then rebuild your Home Manager / NixOS configuration):

```nix
{ lib, pkgs, ... }:
let
  screenMirrorPyEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  screenMirrorTypelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.glib.out
    pkgs.gst_all_1.gstreamer.out
  ];
  screenMirrorGstPluginPath = lib.makeSearchPath "lib/gstreamer-1.0" [
    pkgs.pipewire
    pkgs.gst_all_1.gstreamer.out
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good
  ];
in
{
  home.packages = [
    screenMirrorPyEnv
    pkgs.slurp
  ];

  systemd.user.services.noctalia.Service.Environment = [
    "GI_TYPELIB_PATH=${screenMirrorTypelibPath}"
    "GST_PLUGIN_SYSTEM_PATH_1_0=${screenMirrorGstPluginPath}"
    "LD_LIBRARY_PATH=${lib.makeLibraryPath [ pkgs.wayland ]}"
  ];

  programs.noctalia.settings.plugins = {
    auto_update = "all";
    enabled = [ "fumoctl/portal-screen-mirror" ];
    source = [
      {
        name = "official";
        kind = "git";
        location = "https://github.com/noctalia-dev/official-plugins";
      }
      {
        name = "community";
        kind = "git";
        location = "https://github.com/noctalia-dev/community-plugins";
      }
      {
        name = "fumoctl";
        kind = "git";
        location = "https://github.com/fumoctl/noctalia-plugins";
      }
    ];
  };
}
```

If you install from Noctalia's built-in `community` store (or manage Noctalia via the GUI instead of `programs.noctalia.settings`), you only need the `home.packages` and `systemd.user.services.noctalia.Service.Environment` parts above, then enable `fumoctl/portal-screen-mirror` in **Settings → Plugins** (or via `noctalia msg`).

## Usage

Enable `fumoctl/portal-screen-mirror` in **Settings → Plugins**, then add the `mirror` bar widget to your bar (`type = "fumoctl/portal-screen-mirror:mirror"`) or add the `toggle` tile to Control Center shortcuts.

Clicking the bar widget opens the `controls` panel:

1. Select the **destination screen** (external, unfocused displays such as `HDMI-A-1` sort ahead of `eDP-*` laptop panels).
2. Choose the **frame rate** (`Auto` matches the destination display's live Wayland refresh rate via `wl_output.mode`, or pick `30`, `60`, `120`, or `Uncapped` — can also be changed live while mirroring).
3. Click **Portal Picker (Screen or Window)** to choose any monitor or window via your desktop portal, or **Rectangular Region** to drag a crop box with `slurp`.

While mirroring is active, right-clicking the bar widget (or clicking **Stop Mirroring** inside the panel) stops the stream immediately.

Open or close the panel directly from the command line or a compositor keybind with:

```sh
noctalia msg panel-toggle fumoctl/portal-screen-mirror:controls
```

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `show_cursor` | `bool` | `true` | Embeds the pointer cursor in newly started `ScreenCast` streams (`cursor_mode = 2`). |
| `fit` | `select` | `"contain"` | Controls how the stream scales inside the destination output (`contain`, `cover`, or `stretch`). |
| `max_fps` | `select` | `"auto"` | Default frame rate cap (`"auto"` matches destination display refresh rate, `"30"`, `"60"`, `"120"`, or `"0"` uncapped; also adjustable inside the bar panel). |
| `scale_quality` | `select` | `"balanced"` | Chooses between bilinear downscaling (`"balanced"`) and low-latency nearest-neighbor (`"fast"`). |

## IPC

Address the `mirror-service` entry with the `all` target for keybind workflows:

```sh
# Toggle: stops an active mirror, or opens the destination + source panel
noctalia msg plugin fumoctl/portal-screen-mirror:mirror-service all toggle

# Start portal or region mode directly (optional connector name; defaults to first external output)
noctalia msg plugin fumoctl/portal-screen-mirror:mirror-service all portal HDMI-A-1
noctalia msg plugin fumoctl/portal-screen-mirror:mirror-service all region HDMI-A-1

# Stop an active mirror
noctalia msg plugin fumoctl/portal-screen-mirror:mirror-service all stop
```

## Notes

- **Processes spawned**: `service.luau` launches bundled `companion.py`, which invokes `slurp` only when **Rectangular Region** mode is selected.
- **Filesystem writes**: Writes transient session coordination files (`mirror.run`, `fps.run`, and `stream.sock`), UI frame-rate preference (`prefs.json`), and per-output portal restore tokens (`restore_tokens.json`, mode `0600`) solely inside `noctalia.pluginDataDir()`.
- **Network**: Makes zero network requests; all communication stays local over session D-Bus, Wayland, PipeWire, and an owner-only (`0600`) Unix `SOCK_SEQPACKET` socket.
