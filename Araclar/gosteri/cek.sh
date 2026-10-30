#!/bin/bash
# Tanıtım çekimi: bir sahneyi gösteri moduyla oynatır ve ekranı kaydeder.
# Kullanım: Araclar/gosteri/cek.sh a|b|c <çıktı klasörü>
# Kurulu FingerKit çekim boyunca kapatılır, sonra yeniden açılır.
set -euo pipefail
cd "$(dirname "$0")/../.."
SAHNE=$1
CIKTI=$2
mkdir -p "$CIKTI"
KLASOR=$(mktemp -d)
cp Araclar/gosteri/ayarlar.json "$KLASOR/"
# Pencere: sol, üst, sağ, alt (ekran noktası); trackpad çizimi pencerenin sağ alt köşesinde
SOL=120; UST=90; SAG=1320; ALT=840

osascript -e 'tell application "FingerKit" to quit' 2>/dev/null || true
sleep 1

if [ "$SAHNE" = c ]; then
    # Çekim için yeni belge; adı saklanır, sonunda yalnız o kapanır
    BELGE=$(osascript <<EOS
tell application "TextEdit"
    set d to make new document
    set n to name of d
    activate
    set index of window n to 1
    set bounds of window n to {$SOL, $UST, $SAG, $ALT}
    return n
end tell
EOS
)
else
    PENCERE=$(osascript <<EOS
tell application "Safari"
    make new document with properties {URL:"https://en.wikipedia.org/wiki/Touchpad"}
    tell front window
        make new tab with properties {URL:"https://en.wikipedia.org/wiki/Multi-touch"}
        make new tab with properties {URL:"https://en.wikipedia.org/wiki/Keyboard_shortcut"}
        set current tab to tab 1
    end tell
    set bounds of front window to {$SOL, $UST, $SAG, $ALT}
    activate
    return id of front window
end tell
EOS
)
fi
sleep 3
# İmleç pencerenin ortasına
osascript -l JavaScript -e "ObjC.import('CoreGraphics'); \$.CGWarpMouseCursorPosition({x: $(( (SOL + SAG) / 2 )), y: $(( (UST + ALT) / 2 ))})" >/dev/null

ffmpeg -y -loglevel fatal -f avfoundation -capture_cursor 1 -framerate 30 -i "Capture screen 0:none" \
    -c:v h264_videotoolbox -b:v 20M "$CIKTI/ham-$SAHNE.mov" &
KAYIT=$!
sleep 1.5
FINGERKIT_KLASOR="$KLASOR" FINGERKIT_GOSTERI=$SAHNE FINGERKIT_GOSTERI_PAD="$((SAG - 320)),$((ALT - 256))" \
    build/FingerKit.app/Contents/MacOS/FingerKit -AppleLanguages "(en)" | tee "$CIKTI/gunluk-$SAHNE.txt"
sleep 0.5
kill -INT $KAYIT; wait $KAYIT || true

if [ "$SAHNE" = c ]; then
    # Yalnız çekim için açılan belge kapanır; kullanıcının diğer belgelerine dokunulmaz
    osascript -e "tell application \"TextEdit\" to close document \"$BELGE\" saving no" || true
else
    osascript -e "tell application \"Safari\" to close (every window whose id is $PENCERE)" || true
fi
open -a /Applications/FingerKit.app
echo "✓ $CIKTI/ham-$SAHNE.mov"
