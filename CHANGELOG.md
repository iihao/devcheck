# Changelog

## 0.1.1 — 2026-11-02

- **App icon**: generated from SF Symbols (`scripts/make-icon.sh`), full `.iconset` chain → `Resources/AppIcon.icns`
- `scripts/bundle.sh` embeds the icon and sets `CFBundleIconFile`
- README: logo on both language versions

## 0.1.0 — 2026-11-02

First public release.

- Port map: `lsof` → PID → executable → owning project (`package.json` / `pom.xml` / `go.mod` / `.git`)
- `devcheck why <port>`: explains AirPlay-on-5000, duplicate listeners, fake-alive listeners
- Health rules: duplicate port, unreachable listener, high CPU
- Noise filtering: GUI apps / system daemons hidden by default (`--all` to show)
- Menu bar app (`LSUIElement`) + CLI (`ports`, `doctor`, `menu`, `why`, JSON output)
- Bilingual (en/zh), `LANG`-aware
- Zero dependencies, zero privileges, no network I/O
- 30 unit tests, universal binary (arm64 + x86_64)
