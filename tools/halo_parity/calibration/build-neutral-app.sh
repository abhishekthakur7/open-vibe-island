#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
repository_root="${script_dir:h:h:h}"
source_file="$script_dir/HaloNeutralCalibration.swift"

output_app=""
bundle_id=""
while (( $# > 0 )); do
  case "$1" in
    --output)
      output_app="$2"
      shift 2
      ;;
    --bundle-id)
      bundle_id="$2"
      shift 2
      ;;
    *)
      print -u2 "unknown argument: $1"
      exit 2
      ;;
  esac
done

if [[ -z "$output_app" || -z "$bundle_id" ]]; then
  print -u2 "usage: build-neutral-app.sh --output APP_PATH --bundle-id BUNDLE_ID"
  exit 2
fi

if [[ "$output_app" != "$repository_root"/.build-halo-parity/* ]]; then
  print -u2 "neutral calibration app output must be inside .build-halo-parity"
  exit 2
fi

contents="$output_app/Contents"
macos="$contents/MacOS"
mkdir -p "$macos"

/usr/bin/swiftc \
  -parse-as-library \
  -O \
  -framework AppKit \
  -framework CoreGraphics \
  -framework QuartzCore \
  -framework SwiftUI \
  "$source_file" \
  -o "$macos/HaloNeutralCalibration"

plist="$contents/Info.plist"
/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string en "$plist"
/usr/bin/plutil -insert CFBundleExecutable -string HaloNeutralCalibration "$plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "$bundle_id" "$plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$plist"
/usr/bin/plutil -insert CFBundleName -string "Halo Neutral Calibration" "$plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 1.0 "$plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$plist"
/usr/bin/plutil -insert LSUIElement -bool true "$plist"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$plist"

/usr/bin/codesign --force --deep --sign - "$output_app"
print "$output_app"
