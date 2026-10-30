#!/bin/bash
# Tanıtım videosu (tek çekim, önizleme çizimlerinden): docs/fingerkit-tanitim.mp4 ve .gif
# Önce ./yap.sh --derle. Akış: Sources/FingerKit/UI/PromoStory.swift (PromoStories.all)
set -euo pipefail
cd "$(dirname "$0")/../.."
KARE=$(mktemp -d)
build/FingerKit.app/Contents/MacOS/FingerKit --videolari-ciz "$KARE" -AppleLanguages "(en)" -AppleLocale en_US
ffmpeg -y -loglevel error -framerate 60 -i "$KARE/fingerkit-tanitim/%04d.png" -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -movflags +faststart docs/fingerkit-tanitim.mp4
ffmpeg -y -loglevel error -framerate 60 -i "$KARE/fingerkit-tanitim/%04d.png" \
    -vf "fps=15,scale=800:-1:flags=lanczos,split[x][y];[x]palettegen=max_colors=160:stats_mode=diff[p];[y][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" docs/fingerkit-tanitim.gif
rm -rf "$KARE"
ls -la docs/fingerkit-tanitim.mp4 docs/fingerkit-tanitim.gif
