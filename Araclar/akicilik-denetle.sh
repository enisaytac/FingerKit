#!/bin/bash
# Akıcılık denetimi: sık açılan her pencere ve geçiş ölçülür, sınırı aşan varsa hata verir.
# Ölçülen: ana iş parçacığının en uzun donması (ms). 16 ms bir kare; ~100 ms üstü gözle takılma.
# Kullanım: Araclar/akicilik-denetle.sh   (önce ./yap.sh --derle; yap.sh --surum kendisi çalıştırır)
# Yeni bir pencere/panel eklenince: uygulamaya --<ad>-olc ölçümü ekle, aşağıdaki listeye bir satır yaz.
set -uo pipefail
cd "$(dirname "$0")/.."
APP=build/FingerKit.app/Contents/MacOS/FingerKit
# Ölçüm kullanıcının gerçek ayar ve pano kopyası üzerinde yapılır (boş klasör sorunları gizler); şifre dosyası alınmaz
KLASOR=$(mktemp -d)
rsync -a --exclude imza-sifre "$HOME/Library/Application Support/FingerKit/" "$KLASOR/" 2>/dev/null || true

# ad | nasıl çalıştırılır | sınır (ms) | ilk ölçüm sayılsın mı (ilk açılış da hızlı olmalı)
OLCUMLER=(
  "Sekme geçişi|env FINGERKIT_SEKME_OLC=1|100|evet"
  "Öneri şeridi|env FINGERKIT_SERIT_OLC=1|25|hayir"
  "Pano (⇪+V)|--pano-olc|80|evet"
  "Daire menü|--daire-olc|100|evet"
)

HATA=0
for satir in "${OLCUMLER[@]}"; do
  IFS='|' read -r AD KOMUT SINIR ILK <<< "$satir"
  if [[ $KOMUT == env* ]]; then
    CIKTI=$(env FINGERKIT_KLASOR="$KLASOR" ${KOMUT#env } "$APP" 2>/dev/null)
  else
    CIKTI=$(FINGERKIT_KLASOR="$KLASOR" "$APP" $KOMUT 2>/dev/null)
  fi
  SAYILAR=$(echo "$CIKTI" | grep -E "^(SEKME|SERIT|PANO|DAIRE)" | sed -E 's/^[^:]*: //; s/ ms$//' | tr '\n' ' ')
  [ "$ILK" = hayir ] && SAYILAR=$(echo "$SAYILAR" | cut -d' ' -f2-)
  EN=$(echo "$SAYILAR" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n | tail -1)
  if [ -z "$EN" ]; then
    printf "  ?  %-16s ölçülemedi\n" "$AD"; HATA=1
  elif [ "$EN" -gt "$SINIR" ]; then
    printf "  ✗  %-16s en kötü %4s ms (sınır %s)  [%s]\n" "$AD" "$EN" "$SINIR" "$SAYILAR"; HATA=1
  else
    printf "  ✓  %-16s en kötü %4s ms (sınır %s)\n" "$AD" "$EN" "$SINIR"
  fi
done
rm -rf "$KLASOR"
exit $HATA
