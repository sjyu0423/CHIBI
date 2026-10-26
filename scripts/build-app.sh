#!/bin/sh
set -eu

configuration="${1:-release}"
if [ "${CHIBI_DISABLE_SWIFTPM_SANDBOX:-0}" = "1" ]; then
    swift build -c "$configuration" --disable-sandbox
    bin_path="$(swift build -c "$configuration" --disable-sandbox --show-bin-path)"
else
    swift build -c "$configuration"
    bin_path="$(swift build -c "$configuration" --show-bin-path)"
fi
app_path=".build/CHIBI.app"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/CHIBI" "$app_path/Contents/MacOS/CHIBI"
cp Support/Info.plist "$app_path/Contents/Info.plist"
for resource_bundle in "$bin_path"/*.bundle; do
    if [ -d "$resource_bundle" ]; then
        cp -R "$resource_bundle" "$app_path/Contents/Resources/"
    fi
done
codesign --force --deep --sign - "$app_path" >/dev/null

echo "$app_path"
