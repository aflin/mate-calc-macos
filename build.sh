#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    echo "MATE Calculator for macOS - Build Script"
    echo ""
    echo "Usage: ./build.sh <command>"
    echo ""
    echo "Commands:"
    echo "  compile       Compile the source only (no .app bundle)"
    echo "  light         Compile + lightweight .app bundle (uses Homebrew libs at runtime)"
    echo "  dist          Compile + self-contained .app + DMG (for distribution)"
    echo "  all           Same as dist"
    echo "  clean         Remove all build artifacts"
    echo ""
    echo "Prerequisites:"
    echo "  brew install gtk+3 mpfr libmpc meson itstool pkgconf"
    exit 0
}

do_compile() {
    if [ ! -d build ]; then
        echo "Configuring..."
        meson setup build
    fi
    echo "Building..."
    ninja -C build
}

do_bundle() {
    local flag="${1:-}"
    bash create-macos-bundle.sh $flag

    mv -f "MATE Calculator.app" build/
    for dmg in MATE-Calculator-*.dmg; do
        [ -f "$dmg" ] && mv -f "$dmg" build/
    done

    echo ""
    echo "Output in build/:"
    ls -1 build/MATE* 2>/dev/null
}

do_clean() {
    echo "Cleaning..."
    rm -rf build
    rm -rf "MATE Calculator.app"
    rm -f MATE-Calculator-*.dmg
    echo "Done."
}

case "${1:-}" in
    compile)
        do_compile
        ;;
    light)
        do_compile
        do_bundle --light
        ;;
    dist|all)
        do_compile
        do_bundle
        ;;
    clean)
        do_clean
        ;;
    *)
        usage
        ;;
esac
