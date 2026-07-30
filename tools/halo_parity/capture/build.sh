#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
output_dir="$script_dir/bin"
mkdir -p "$output_dir"

xcrun swiftc \
  -parse-as-library \
  -O \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ScreenCaptureKit \
  "$script_dir/HaloWindowCapture.swift" \
  -o "$output_dir/halo-window-capture"

shasum -a 256 "$output_dir/halo-window-capture"
