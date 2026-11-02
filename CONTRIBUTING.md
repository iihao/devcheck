# Contributing to DevCheck

Thanks for helping. This project stays deliberately small: **no third-party dependencies, no privileged code, no network calls.** Please keep it that way in PRs.

## Development

```bash
git clone https://github.com/iihao/devcheck.git
cd devcheck
swift build          # compile
swift test           # 30 tests, must stay green
.build/debug/devcheck doctor
```

Requirements: macOS 14+, Xcode 16+ (Swift 6 toolchain).

## Layout

| Path | What goes here |
|---|---|
| `Sources/DevCheckCore/` | Pure logic. **No AppKit imports.** Everything here must be unit-testable. |
| `Sources/DevCheckApp/` | Menu bar + CLI. Thin: format and wire, don't compute. |
| `Tests/DevCheckCoreTests/` | Pure-function tests. |

## Ground rules

1. **No new dependencies.** If you need something, write it (see `TCProbe.swift`, 90 lines instead of a package).
2. **No `sudo`, no privileged helper** in the default path. Root-owned ports are read-only on purpose.
3. **No network I/O.** The only sockets allowed are loopback handshakes.
4. **Parsers need tests.** `lsof`/`ps` output is parsed by hand — any change to parsing requires a test with a realistic sample.
5. **Classifier changes need a regression test.** The `PortSource` logic has bitten us twice already (Homebrew's `.git`, Xcode's `python3` inside `Python.app`); see `PortSourceRegressionTests`.

## Good first issues

Look for the `good first issue` label. Typical ones:
- Add a known service to `PortExplainer.knownCommands`
- Improve a table column width in the CLI output
- Add a new `PortSource` regression case

## Commit / PR

- Conventional commits appreciated: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`.
- One concern per PR. Include a screenshot or terminal output when behavior changes.
- CI runs `swift test` on macOS; keep it green.

## Reporting bugs

Use the bug template and include:

- `devcheck --version`
- `sw_vers`
- The output of `devcheck doctor` (redact paths if needed)
- What you expected vs. what you saw
