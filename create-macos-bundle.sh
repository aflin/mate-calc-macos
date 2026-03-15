#!/bin/bash
set -e

# Create a macOS .app bundle for MATE Calculator.
# Run this script from the mate-calc source directory after building.
#
# Usage:
#   bash create-macos-bundle.sh              # Self-contained bundle + DMG (for distribution)
#   bash create-macos-bundle.sh --light      # Lightweight bundle using Homebrew libs (personal use)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MATE Calculator"
APP_BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

BINARY_SRC="${SCRIPT_DIR}/build/src/mate-calc"
ICON_SRC="${SCRIPT_DIR}/mate-calc.png"
SCHEMA_SRC="${SCRIPT_DIR}/data/org.mate.calc.gschema.xml"

HOMEBREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"

LIGHT=false
if [ "${1:-}" = "--light" ]; then
    LIGHT=true
fi

if $LIGHT; then
    echo "Creating lightweight macOS app bundle (requires Homebrew at runtime)"
else
    echo "Creating self-contained macOS app bundle (for distribution)"
fi

# ── Clean any previous bundle ────────────────────────────────────────────────
if [ -d "${APP_BUNDLE}" ]; then
    echo "Removing existing bundle..."
    rm -rf "${APP_BUNDLE}"
fi

# ── 1. Create directory structure ────────────────────────────────────────────
echo "Creating directory structure..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

SCHEMAS_DIR="${RESOURCES_DIR}/share/glib-2.0/schemas"
mkdir -p "${SCHEMAS_DIR}"

if ! $LIGHT; then
    FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
    PIXBUF_DIR="${RESOURCES_DIR}/lib/gdk-pixbuf-2.0/2.10.0"
    PIXBUF_LOADERS_DIR="${PIXBUF_DIR}/loaders"
    mkdir -p "${FRAMEWORKS_DIR}"
    mkdir -p "${PIXBUF_LOADERS_DIR}"
fi

# ── 2. Create Info.plist ─────────────────────────────────────────────────────
echo "Writing Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MATE Calculator</string>
    <key>CFBundleDisplayName</key>
    <string>MATE Calculator</string>
    <key>CFBundleIdentifier</key>
    <string>org.mate-desktop.mate-calc</string>
    <key>CFBundleVersion</key>
    <string>1.28.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.28.0</string>
    <key>CFBundleExecutable</key>
    <string>mate-calc-launcher</string>
    <key>CFBundleIconFile</key>
    <string>mate-calc.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
</dict>
</plist>
PLIST

# ── 3. Copy the built binary ────────────────────────────────────────────────
echo "Copying mate-calc binary..."
if [ ! -f "${BINARY_SRC}" ]; then
    echo "ERROR: Binary not found at ${BINARY_SRC}" >&2
    echo "       Please build first: meson setup build && ninja -C build" >&2
    exit 1
fi
cp "${BINARY_SRC}" "${MACOS_DIR}/mate-calc"

# ── 4. Bundle dylib dependencies (full mode only) ───────────────────────────
if ! $LIGHT; then
    echo "Bundling dylib dependencies..."

    collect_deps() {
        otool -L "$1" 2>/dev/null | awk '{print $1}' | while read -r lib; do
            case "$lib" in
                /usr/lib/*|/System/*|@*|*:) continue ;;
            esac
            echo "$lib"
        done
    }

    SEEN_FILE="$(mktemp)"
    trap "rm -f '$SEEN_FILE'" EXIT

    is_seen() {
        grep -qxF "$1" "$SEEN_FILE" 2>/dev/null
    }
    mark_seen() {
        echo "$1" >> "$SEEN_FILE"
    }

    QUEUE_FILE="$(mktemp)"
    DEPS_FILE="$(mktemp)"
    echo "${MACOS_DIR}/mate-calc" > "$QUEUE_FILE"

    while [ -s "$QUEUE_FILE" ]; do
        current="$(head -1 "$QUEUE_FILE")"
        tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"

        collect_deps "$current" > "$DEPS_FILE"
        while IFS= read -r dep; do
            [ -z "$dep" ] && continue
            base="$(basename "$dep")"

            if ! is_seen "$base"; then
                mark_seen "$base"
                if [ -f "$dep" ]; then
                    cp -L "$dep" "${FRAMEWORKS_DIR}/${base}"
                    chmod 644 "${FRAMEWORKS_DIR}/${base}"
                    echo "${FRAMEWORKS_DIR}/${base}" >> "$QUEUE_FILE"
                fi
            fi
        done < "$DEPS_FILE"
    done
    rm -f "$QUEUE_FILE" "$DEPS_FILE"

    BUNDLED_COUNT=$(ls -1 "${FRAMEWORKS_DIR}"/*.dylib 2>/dev/null | wc -l | tr -d ' ')
    echo "  Found ${BUNDLED_COUNT} libraries to bundle"

    # ── 5. Rewrite library paths ─────────────────────────────────────────────
    echo "Rewriting library load paths..."

    rewrite_deps() {
        local binary="$1"
        local binary_base="$(basename "$binary")"

        local current_id
        current_id="$(otool -D "$binary" 2>/dev/null | tail -1)"
        if [ -n "$current_id" ] && [ "$current_id" != "$binary" ]; then
            install_name_tool -id "@executable_path/../Frameworks/${binary_base}" "$binary" 2>/dev/null || true
        fi

        otool -L "$binary" 2>/dev/null | awk '{print $1}' | while read -r lib; do
            case "$lib" in
                /usr/lib/*|/System/*|@*|*:) continue ;;
            esac
            local lib_base="$(basename "$lib")"
            if [ -f "${FRAMEWORKS_DIR}/${lib_base}" ]; then
                install_name_tool -change "$lib" "@executable_path/../Frameworks/${lib_base}" "$binary" 2>/dev/null || true
            fi
        done
    }

    rewrite_deps "${MACOS_DIR}/mate-calc"

    for dylib in "${FRAMEWORKS_DIR}"/*.dylib; do
        [ -f "$dylib" ] && rewrite_deps "$dylib"
    done

    # ── 6. Bundle GDK pixbuf loaders ─────────────────────────────────────────
    echo "Bundling GDK pixbuf loaders..."

    echo "  Generating pixbuf loaders.cache from Homebrew originals..."
    "${HOMEBREW_PREFIX}/bin/gdk-pixbuf-query-loaders" \
        "${HOMEBREW_PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders"/*.so \
        > "${PIXBUF_DIR}/loaders.cache" 2>/dev/null || true

    sed -i '' "s|${HOMEBREW_PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders|BUNDLE_LOADERS_DIR|g" "${PIXBUF_DIR}/loaders.cache"

    PIXBUF_SRC="${HOMEBREW_PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders"
    if [ -d "$PIXBUF_SRC" ]; then
        for loader in "${PIXBUF_SRC}"/*.so; do
            [ -f "$loader" ] || continue
            base="$(basename "$loader")"
            cp -L "$loader" "${PIXBUF_LOADERS_DIR}/${base}"
            chmod 644 "${PIXBUF_LOADERS_DIR}/${base}"

            otool -L "${PIXBUF_LOADERS_DIR}/${base}" 2>/dev/null | awk '{print $1}' | while read -r lib; do
                case "$lib" in
                    /usr/lib/*|/System/*|@*|*:) continue ;;
                esac
                lib_base="$(basename "$lib")"
                if [ -f "${FRAMEWORKS_DIR}/${lib_base}" ]; then
                    install_name_tool -change "$lib" "@executable_path/../Frameworks/${lib_base}" "${PIXBUF_LOADERS_DIR}/${base}" 2>/dev/null || true
                else
                    if [ -f "$lib" ]; then
                        cp -L "$lib" "${FRAMEWORKS_DIR}/${lib_base}"
                        chmod 644 "${FRAMEWORKS_DIR}/${lib_base}"
                        rewrite_deps "${FRAMEWORKS_DIR}/${lib_base}"
                        install_name_tool -change "$lib" "@executable_path/../Frameworks/${lib_base}" "${PIXBUF_LOADERS_DIR}/${base}" 2>/dev/null || true
                    fi
                fi
            done
        done
    fi
fi

# ── 7. Bundle GSettings schemas ─────────────────────────────────────────────
echo "Bundling GSettings schemas..."
cp "${SCHEMA_SRC}" "${SCHEMAS_DIR}/"

for schema in "${HOMEBREW_PREFIX}/share/glib-2.0/schemas"/org.gtk.Settings.*.gschema.xml \
              "${HOMEBREW_PREFIX}/share/glib-2.0/schemas"/gschemas.compiled; do
    [ -f "$schema" ] && cp "$schema" "${SCHEMAS_DIR}/"
done

"${HOMEBREW_PREFIX}/bin/glib-compile-schemas" "${SCHEMAS_DIR}"

# ── 8. Bundle hicolor icon theme (for menu icons) ───────────────────────────
echo "Bundling icon themes..."
ICONS_DIR="${RESOURCES_DIR}/share/icons"
mkdir -p "${ICONS_DIR}"

if [ -d "${HOMEBREW_PREFIX}/share/icons/hicolor" ]; then
    cp -R "${HOMEBREW_PREFIX}/share/icons/hicolor" "${ICONS_DIR}/"
fi

# ── 9. Convert PNG icon to .icns ────────────────────────────────────────────
echo "Converting app icon to .icns format..."
if [ ! -f "${ICON_SRC}" ]; then
    echo "WARNING: Icon not found at ${ICON_SRC}, skipping" >&2
else
    ICONSET_DIR=$(mktemp -d)/mate-calc.iconset
    mkdir -p "${ICONSET_DIR}"

    for SIZE in 16 32 64 128 256 512; do
        sips -z ${SIZE} ${SIZE} "${ICON_SRC}" --out "${ICONSET_DIR}/icon_${SIZE}x${SIZE}.png" > /dev/null 2>&1
    done
    for SIZE in 16 32 128 256 512; do
        DOUBLE=$((SIZE * 2))
        sips -z ${DOUBLE} ${DOUBLE} "${ICON_SRC}" --out "${ICONSET_DIR}/icon_${SIZE}x${SIZE}@2x.png" > /dev/null 2>&1
    done

    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/mate-calc.icns"
    rm -rf "$(dirname "${ICONSET_DIR}")"
fi

# ── 10. Create launcher script ───────────────────────────────────────────────
echo "Creating launcher script..."

if $LIGHT; then
    # Light mode: point to Homebrew at runtime
    cat > "${MACOS_DIR}/mate-calc-launcher" << LAUNCHER
#!/bin/bash

LAUNCHER_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
RESOURCES_DIR="\${LAUNCHER_DIR}/../Resources"

export GDK_PIXBUF_MODULE_FILE="${HOMEBREW_PREFIX}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
export GSETTINGS_SCHEMA_DIR="\${RESOURCES_DIR}/share/glib-2.0/schemas"
export XDG_DATA_DIRS="\${RESOURCES_DIR}/share:${HOMEBREW_PREFIX}/share:/usr/local/share:/usr/share"
export GTK_PATH="${HOMEBREW_PREFIX}/lib/gtk-3.0"
export DYLD_FALLBACK_LIBRARY_PATH="${HOMEBREW_PREFIX}/lib"

exec "\${LAUNCHER_DIR}/mate-calc" "\$@"
LAUNCHER
else
    # Full mode: use only bundled resources
    cat > "${MACOS_DIR}/mate-calc-launcher" << 'LAUNCHER'
#!/bin/bash

LAUNCHER_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="${LAUNCHER_DIR}/../Resources"
FRAMEWORKS_DIR="${LAUNCHER_DIR}/../Frameworks"

PIXBUF_CACHE="${RESOURCES_DIR}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
PIXBUF_LOADERS="${RESOURCES_DIR}/lib/gdk-pixbuf-2.0/2.10.0/loaders"
if [ -f "${PIXBUF_CACHE}" ]; then
    RUNTIME_CACHE=$(mktemp)
    sed "s|BUNDLE_LOADERS_DIR|${PIXBUF_LOADERS}|g" "${PIXBUF_CACHE}" > "${RUNTIME_CACHE}"
    export GDK_PIXBUF_MODULE_FILE="${RUNTIME_CACHE}"
fi

export GSETTINGS_SCHEMA_DIR="${RESOURCES_DIR}/share/glib-2.0/schemas"
export XDG_DATA_DIRS="${RESOURCES_DIR}/share:/usr/local/share:/usr/share"
export DYLD_FALLBACK_LIBRARY_PATH="${FRAMEWORKS_DIR}"

exec "${LAUNCHER_DIR}/mate-calc" "$@"
LAUNCHER
fi

chmod +x "${MACOS_DIR}/mate-calc-launcher"

# ── 11. Ad-hoc code signing ─────────────────────────────────────────────────
echo "Code signing (ad-hoc)..."

if ! $LIGHT; then
    for dylib in "${FRAMEWORKS_DIR}"/*.dylib; do
        [ -f "$dylib" ] && codesign --force --sign - "$dylib" 2>/dev/null
    done

    for loader in "${PIXBUF_LOADERS_DIR}"/*.so; do
        [ -f "$loader" ] && codesign --force --sign - "$loader" 2>/dev/null
    done
fi

codesign --force --sign - "${MACOS_DIR}/mate-calc"
codesign --force --sign - --deep "${APP_BUNDLE}"

echo "  Verifying signature..."
codesign --verify --verbose "${APP_BUNDLE}" 2>&1 || echo "  (verification note: ad-hoc signatures may show warnings, this is expected)"

# ── 12. Create DMG with Applications symlink (full mode only) ────────────────
if ! $LIGHT; then
    echo "Creating DMG installer..."

    DMG_NAME="MATE-Calculator-1.28.0"
    DMG_DIR="$(mktemp -d)"
    DMG_PATH="${SCRIPT_DIR}/${DMG_NAME}.dmg"

    rm -f "${DMG_PATH}"

    cp -R "${APP_BUNDLE}" "${DMG_DIR}/"
    ln -s /Applications "${DMG_DIR}/Applications"

    RW_DMG="${SCRIPT_DIR}/${DMG_NAME}-rw.dmg"
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${DMG_DIR}" \
        -ov -format UDRW \
        "${RW_DMG}" >/dev/null

    MOUNT_OUT="$(hdiutil attach "${RW_DMG}" -readwrite -noverify -noautoopen)"
    MOUNT_POINT="$(echo "$MOUNT_OUT" | grep "/Volumes/" | sed 's|.*\(/Volumes/.*\)|\1|')"

    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${APP_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 640, 400}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set position of item "${APP_NAME}.app" of container window to {140, 150}
        set position of item "Applications" of container window to {400, 150}
        close
    end tell
end tell
APPLESCRIPT

    sync
    sleep 1

    hdiutil detach "$MOUNT_POINT" -quiet

    hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" >/dev/null
    rm -f "${RW_DMG}"
    rm -rf "${DMG_DIR}"

    DMG_SIZE=$(du -sh "${DMG_PATH}" | awk '{print $1}')
fi

# ── Report ───────────────────────────────────────────────────────────────────
BUNDLE_SIZE=$(du -sh "${APP_BUNDLE}" | awk '{print $1}')

echo ""
echo "========================================="
echo " SUCCESS"
echo ""
echo " ${APP_NAME}.app created at:"
echo " ${APP_BUNDLE}"
echo " Bundle size: ${BUNDLE_SIZE}"

if $LIGHT; then
    echo ""
    echo " Mode: lightweight (uses Homebrew libs)"
    echo " Requires Homebrew with gtk+3 installed."
else
    DYLIB_COUNT=$(ls -1 "${FRAMEWORKS_DIR}"/*.dylib 2>/dev/null | wc -l | tr -d ' ')
    LOADER_COUNT=$(ls -1 "${PIXBUF_LOADERS_DIR}"/*.so 2>/dev/null | wc -l | tr -d ' ')
    echo " Bundled dylibs: ${DYLIB_COUNT}"
    echo " Pixbuf loaders: ${LOADER_COUNT}"
    echo ""
    echo " DMG installer created at:"
    echo " ${DMG_PATH} (${DMG_SIZE})"
    echo ""
    echo " This bundle is self-contained and can be"
    echo " copied to another Mac (same architecture)."
fi
echo "========================================="
