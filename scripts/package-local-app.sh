#!/bin/zsh
# Build a local-only Open Island bundle and ZIP archive.
#
# This script never resolves dependencies, contacts a notary service, uploads,
# publishes, creates a feed, or mutates a remote service. It requires the
# checkout's SwiftPM dependencies to be available locally.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Open Island packaging runs only on macOS." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="${OPEN_ISLAND_APP_NAME:-Open Island}"
bundle_identifier="${OPEN_ISLAND_BUNDLE_ID:-app.openisland.local}"
version="${OPEN_ISLAND_VERSION:-0.1.0}"
build_number="${OPEN_ISLAND_BUILD_NUMBER:-$(git -C "$repo_root" rev-list --count HEAD 2>/dev/null || echo 1)}"
package_root="${OPEN_ISLAND_PACKAGE_ROOT:-$repo_root/output/local-package}"
bundle_dir="${OPEN_ISLAND_BUNDLE_DIR:-$package_root/$app_name.app}"
zip_path="${OPEN_ISLAND_ZIP_PATH:-$package_root/$app_name.zip}"
entitlements_path="$repo_root/config/packaging/OpenIslandApp.entitlements"
local_identity_name="Open Island Dev Local"

if [[ "$bundle_dir" != "$package_root/"*.app || "$zip_path" != "$package_root/"*.zip ]]; then
    echo "Local package outputs must stay under OPEN_ISLAND_PACKAGE_ROOT." >&2
    exit 1
fi

cd "$repo_root"
swift build --disable-automatic-resolution -c release --product OpenIslandApp
swift build --disable-automatic-resolution -c release --product OpenIslandHooks
swift build --disable-automatic-resolution -c release --product OpenIslandSetup

build_bin_dir="$(swift build --disable-automatic-resolution -c release --show-bin-path)"
app_binary="$build_bin_dir/OpenIslandApp"
hooks_binary="$build_bin_dir/OpenIslandHooks"
setup_binary="$build_bin_dir/OpenIslandSetup"
brand_icon="$repo_root/Assets/Brand/OpenIsland.icns"
resource_bundle="$build_bin_dir/OpenIsland_OpenIslandApp.bundle"

for required in "$app_binary" "$hooks_binary" "$setup_binary" "$brand_icon" "$resource_bundle"; do
    if [[ ! -e "$required" ]]; then
        echo "Missing local packaging input: $required" >&2
        exit 1
    fi
done

rm -rf "$bundle_dir" "$zip_path"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Helpers" "$bundle_dir/Contents/Resources"

cp "$app_binary" "$bundle_dir/Contents/MacOS/OpenIslandApp"
cp "$hooks_binary" "$bundle_dir/Contents/Helpers/OpenIslandHooks"
cp "$setup_binary" "$bundle_dir/Contents/Helpers/OpenIslandSetup"
cp "$brand_icon" "$bundle_dir/Contents/Resources/OpenIsland.icns"
cp -R "$resource_bundle" "$bundle_dir/Contents/Resources/"
chmod +x "$bundle_dir/Contents/MacOS/OpenIslandApp" \
    "$bundle_dir/Contents/Helpers/OpenIslandHooks" \
    "$bundle_dir/Contents/Helpers/OpenIslandSetup"

cat > "$bundle_dir/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$app_name</string>
    <key>CFBundleExecutable</key>
    <string>OpenIslandApp</string>
    <key>CFBundleIconFile</key>
    <string>OpenIsland</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_identifier</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Open Island needs automation access to focus Terminal and iTerm sessions for jump-back.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

plutil -lint "$bundle_dir/Contents/Info.plist" >/dev/null

sign_identity="-"
if security find-identity -p codesigning -v "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
        | grep -q "\"$local_identity_name\""; then
    sign_identity="$local_identity_name"
fi

codesign --force --sign "$sign_identity" "$bundle_dir/Contents/Helpers/OpenIslandHooks"
codesign --force --sign "$sign_identity" "$bundle_dir/Contents/Helpers/OpenIslandSetup"
codesign --force --sign "$sign_identity" --entitlements "$entitlements_path" "$bundle_dir"
codesign --verify --deep --strict --verbose=2 "$bundle_dir"

ditto -c -k --keepParent "$bundle_dir" "$zip_path"

echo "Local bundle: $bundle_dir"
echo "Local archive: $zip_path"
echo "Signed with local identity: $sign_identity"
