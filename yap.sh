#!/bin/bash
# FingerKit'i derler, uygulama paketi yapar, imzalar, /Applications'a kurar ve açar.
# Kullanım: ./yap.sh            (derle, kur, aç)
#           ./yap.sh --derle    (yalnız derle ve imzala; build/FingerKit.app)
#           ./yap.sh --surum    (herkese dağıtılacak sürüm: Apple Silicon + Intel, yerel imza,
#                                build/FingerKit-<sürüm>.zip ve SHA-256; kurmaz)
set -euo pipefail
cd "$(dirname "$0")"

APP=FingerKit
BUNDLE="build/$APP.app"
DEST="/Applications/$APP.app"

# Kalıcı imza kimliği: macOS verilen izni (Erişilebilirlik) imzaya bağlar. Her derlemede aynı
# kimlikle imzalanınca izin bir kez verilir, yeniden derlemede kaybolmaz.
# Kimlik ayrı bir anahtar zincirinde durur; şifresi depo dışında, rastgele üretilmiş bir dosyadadır.
IDENTITY="FingerKit imza"
KEYCHAIN="$HOME/Library/Keychains/FingerKit-imza.keychain-db"
PASSFILE="$HOME/Library/Application Support/FingerKit/imza-sifre"

imza_kimligi_kur() {
    if [ -f "$KEYCHAIN" ] && security find-identity -p codesigning "$KEYCHAIN" | grep -q "$IDENTITY"; then
        return
    fi
    echo "→ İmza kimliği oluşturuluyor (yalnız ilk sefer)"
    mkdir -p "$(dirname "$PASSFILE")"
    if [ ! -f "$PASSFILE" ]; then
        (umask 077; /usr/bin/openssl rand -hex 16 >"$PASSFILE")
    fi
    local pw tmp
    pw=$(cat "$PASSFILE")
    tmp=$(mktemp -d)
    cat >"$tmp/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cfg" \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$IDENTITY" \
        -out "$tmp/id.p12" -passout pass:"$pw"
    [ -f "$KEYCHAIN" ] || security create-keychain -p "$pw" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$pw" "$KEYCHAIN"
    security import "$tmp/id.p12" -k "$KEYCHAIN" -P "$pw" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pw" "$KEYCHAIN" >/dev/null
    rm -rf "$tmp"
}

# codesign kimliği yalnız arama listesindeki anahtar zincirlerinde bulur; listedekiler korunarak eklenir
zinciri_listeye_ekle() {
    security list-keychains -d user | grep -q "FingerKit-imza" && return
    local list=() line
    while IFS= read -r line; do
        line="${line//\"/}"
        line="${line#"${line%%[![:space:]]*}"}"
        list+=("$line")
    done < <(security list-keychains -d user)
    security list-keychains -d user -s "${list[@]}" "$KEYCHAIN"
}

if [ "${1:-}" = "--surum" ]; then
    echo "→ Derleniyor (Apple Silicon + Intel)"
    swift build -c release --triple arm64-apple-macosx15.0
    swift build -c release --triple x86_64-apple-macosx15.0
    BIN="build/$APP-universal"
    mkdir -p build
    lipo -create -output "$BIN" \
        "$(swift build -c release --triple arm64-apple-macosx15.0 --show-bin-path)/$APP" \
        "$(swift build -c release --triple x86_64-apple-macosx15.0 --show-bin-path)/$APP"
else
    echo "→ Derleniyor"
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/$APP"
fi

echo "→ Paket hazırlanıyor"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"
cp Paket/Info.plist "$BUNDLE/Contents/"
cp Paket/FingerKit.icns "$BUNDLE/Contents/Resources/"
# Arayüz dilleri: Mac'in dili neyse o .lproj kullanılır
cp -R Paket/Diller/*.lproj "$BUNDLE/Contents/Resources/"

if [ "${1:-}" = "--surum" ]; then
    # Başkalarının Mac'inde bizim anahtar zincirimiz yok: yerel (ad-hoc) imza, Apple onaysız
    echo "→ İmzalanıyor (yerel imza)"
    codesign --force --sign - --timestamp=none "$BUNDLE"
    codesign --verify --strict "$BUNDLE"
    # Takılan pencere yayına çıkmasın: sık açılan her pencerenin donma süresi sınırın altında olmalı
    # GitHub'ın sanal Mac'inde ekran yok ve ölçüm anlamsız: orada atlanır, etiketten önce bu Mac'te ölçülür
    if [ -n "${CI:-}" ]; then
        echo "→ Akıcılık denetimi atlandı (CI)"
    else
        echo "→ Akıcılık denetimi"
        Araclar/akicilik-denetle.sh || { echo "✗ Akıcılık sınırı aşıldı; sürüm yapılmadı"; exit 1; }
    fi
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Paket/Info.plist)
    ZIP="build/$APP-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$BUNDLE" "$ZIP"
    echo "✓ Sürüm hazır: $ZIP"
    echo "  SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
    exit 0
fi

echo "→ İmzalanıyor"
imza_kimligi_kur
zinciri_listeye_ekle
security unlock-keychain -p "$(cat "$PASSFILE")" "$KEYCHAIN"
HASH=$(security find-identity -p codesigning "$KEYCHAIN" | awk -v id="\"$IDENTITY\"" '$0 ~ id { print $2; exit }')
codesign --force --sign "$HASH" --timestamp=none "$BUNDLE"
[ "${1:-}" = "--derle" ] && { echo "✓ Hazır: $BUNDLE"; exit 0; }

echo "→ Kuruluyor: $DEST"
if pgrep -x "$APP" >/dev/null; then
    pkill -x "$APP" || true
    for _ in $(seq 1 25); do pgrep -x "$APP" >/dev/null || break; sleep 0.2; done
fi
rm -rf "$DEST"
ditto "$BUNDLE" "$DEST"
open "$DEST"
echo "✓ FingerKit açıldı (menü çubuğunda el simgesi)"
