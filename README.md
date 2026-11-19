# noctalia-plugins

Personal [Noctalia](https://github.com/noctalia-dev/noctalia) plugin source repository.

## Plugins

- [`fumoctl/portal-screen-mirror`](portal-screen-mirror/README.md) — Mirror any screen, window, or rectangular region onto another display via XDG `ScreenCast` and a `zwlr-layer-shell-v1` overlay surface.

## Using as a Noctalia Git Source

```sh
noctalia msg plugins source add fumoctl git https://github.com/fumoctl/noctalia-plugins
noctalia msg plugins enable fumoctl/portal-screen-mirror
```

## Opening a PR to `noctalia-dev/community-plugins`

1. Fork and clone `https://github.com/noctalia-dev/community-plugins`, then create a branch.
2. Copy `portal-screen-mirror/` into the root of that checkout (`cp -r portal-screen-mirror /path/to/community-plugins/`).
   - Do **not** copy `catalog.toml` — `community-plugins` regenerates its `catalog.toml` automatically in CI.
   - Optionally replace `portal-screen-mirror/thumbnail.webp` with a live screenshot exported via <https://assets.noctalia.dev/plugins/thumbnail-generator.html> (`960x540` WebP).
3. Commit and open a PR against `noctalia-dev/community-plugins:main`.
