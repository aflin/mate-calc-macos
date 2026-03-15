# MATE Calculator for macOS

![mate-calc-icon](mate-calc.png)

A port of [MATE Calculator](https://github.com/mate-desktop/mate-calc) to macOS. MATE Calculator is a powerful graphical calculator with basic, advanced, financial, and programming modes, using GNU MPFR and GNU MPC for arbitrary-precision arithmetic.

It originates from *calctool*, written for Sun's OpenWindows DeskSet in the late 1980s, which later became *gnome-calc* in GNOME 2, and then *mate-calc* when the MATE desktop forked from GNOME 2. This fork adds macOS support: Cmd key shortcuts, a self-contained .app bundle with all dependencies included, and a DMG installer.

## Prerequisites

Install the build dependencies via [Homebrew](https://brew.sh):

```
brew install gtk+3 mpfr libmpc meson itstool pkgconf
```

## Building

```
./build.sh          # show usage
./build.sh compile  # compile only
./build.sh light    # compile + lightweight .app (uses Homebrew libs at runtime)
./build.sh dist     # compile + self-contained .app + DMG (for distribution)
./build.sh all      # same as dist
./build.sh clean    # remove all build artifacts
```

The `compile` target produces two binaries in `build/src/`:

- `mate-calc` — the GUI calculator
- `mate-calc-cmd` — a command-line calculator

The `light` and `dist` targets place the `.app` (and DMG for `dist`) in `build/`.

The **lightweight** bundle (~1 MB) requires Homebrew with gtk+3 on the target machine. The **dist** bundle (~9 MB DMG) is self-contained with all dylibs included, ad-hoc signed, and portable to any arm64 Mac running macOS 11+.

Recipients of the DMG may need to right-click and select Open on first launch to bypass Gatekeeper since the app is not notarized.

## Changes from upstream

- `meson.build` — added Homebrew include/library paths for MPFR and MPC
- `src/mp.h` — added `typedef unsigned long ulong` for macOS (Linux defines this in `sys/types.h`)
- `src/math-window.c`, `src/math-display.c` — keyboard shortcuts use Cmd instead of Ctrl on macOS
- `src/math-buttons.c` — button tooltips show the correct modifier key per platform
- `src/math-display.c` — quoted CSS `font-family` value to fix a GTK theme parsing warning; use system font with full Unicode coverage on macOS
- `build.sh` — top-level build script with compile, light, dist, and clean targets
- `create-macos-bundle.sh` — builds the .app bundle and DMG

## Acknowledgements

See the upstream [AUTHORS](https://github.com/mate-desktop/mate-calc/blob/master/AUTHORS) file for the full list of contributors.

## License

GPL-2.0-or-later. See the upstream [MATE Calculator](https://github.com/mate-desktop/mate-calc) repository for full license text.
