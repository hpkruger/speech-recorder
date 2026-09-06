#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
iconset_path="$PWD/build/AppIcon.iconset"
mkdir -p "$iconset_path"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out "$iconset_path/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Assets/AppIcon.png --out "$iconset_path/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_path" -o Assets/AppIcon.icns
