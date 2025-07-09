#!/bin/bash

set -e
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Ten skrypt musi być uruchomiony jako root lub przez sudo.${NC}"
  exit 1
fi

echo "🔄 Aktualizuję listę pakietów i wykonuję upgrade systemu..."
apt update && apt upgrade -y

# 📁 Logowanie wszystkiego do pliku
LOGFILE="instalacja_windowsa_$(date +%F_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# 🔧 Instalacja wymaganych narzędzi
echo "📦 Instaluję potrzebne pakiety..."
apt install -y util-linux curl wget nano sudo fdisk pigz

# 🔍 Lista dysków
echo "📄 Lista dostępnych dysków:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk || {
  echo -e "${RED}❌ Nie udało się wyświetlić listy dysków${NC}"
  exit 1
}

# 🔽 Wybór dysku
read -p "Podaj nazwę dysku do instalacji Windowsa (np. sdb): " DESTINATION_DEVICE

if [ ! -b "/dev/$DESTINATION_DEVICE" ]; then
  echo -e "${RED}❌ Dysk /dev/$DESTINATION_DEVICE nie istnieje!${NC}"
  exit 1
fi

# 🚫 Sprawdź, czy to nie dysk systemowy
ROOT_DISK=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
if [[ "/dev/$DESTINATION_DEVICE" == "$ROOT_DISK" ]]; then
  echo -e "${RED}⚠️ Uwaga! Wybrany dysk to aktualny dysk systemowy: $ROOT_DISK${NC}"
  read -p "Na pewno kontynuować? (wszystko zostanie utracone!) [tak/nie]: " ROOT_CONFIRM
  [[ "$ROOT_CONFIRM" =~ ^(tak|t|yes|y)$ ]] || exit 1
fi

# 🧪 Sprawdzenie partycji
echo "🔎 Sprawdzam partycje na dysku /dev/$DESTINATION_DEVICE..."
PARTS=$(lsblk /dev/$DESTINATION_DEVICE -no PARTTYPE | grep -v '^$' || true)

# Odmontowywanie zamontowanych partycji
MOUNTED_PARTS=$(lsblk /dev/$DESTINATION_DEVICE -no MOUNTPOINT | grep -v '^$' || true)
if [ -n "$MOUNTED_PARTS" ]; then
  echo "⚠️ Na dysku /dev/$DESTINATION_DEVICE są zamontowane partycje. Odmontowuję je..."
  for mp in $MOUNTED_PARTS; do
    echo "🚪 Odmontowuję $mp"
    umount "$mp" || {
      echo -e "${RED}❌ Nie udało się odmontować $mp${NC}"
      exit 1
    }
  done
fi

if [ -n "$PARTS" ]; then
  echo -e "${RED}⚠️ Dysk ma partycje!${NC}"
  read -p "Czy wyczyścić dysk? (wszystko zostanie usunięte) [tak/nie]: " ANSWER
  if [[ "$ANSWER" =~ ^(tak|t|y|yes)$ ]]; then
    echo "🧹 Czyszczenie dysku..."
    wipefs -a /dev/$DESTINATION_DEVICE || {
      echo -e "${RED}❌ wipefs się nie powiódł${NC}"
      exit 1
    }
    echo "🧨 Zeruję pierwsze 10MB (MBR/EFI)..."
    dd if=/dev/zero of=/dev/$DESTINATION_DEVICE bs=1M count=10 status=none
  else
    echo -e "${RED}❌ Anulowano czyszczenie dysku. Kończę.${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}✅ Dysk jest pusty.${NC}"
fi

# 📥 Pobieranie obrazu
IMAGE_URL="https://huggingface.co/ngxson/windows-10-ggcloud/resolve/main/windows-10-ggcloud.raw.gz"

if [[ -f windows.raw.gz ]]; then
  OLDTIME=$(find windows.raw.gz -mtime +7)
  if [[ -n "$OLDTIME" ]]; then
    echo "🗑️ Usuwam stary plik windows.raw.gz (starszy niż 7 dni)..."
    rm windows.raw.gz
  else
    echo -e "${GREEN}📦 Plik windows.raw.gz jest aktualny – pomijam pobieranie.${NC}"
  fi
fi

if [[ ! -f windows.raw.gz ]]; then
  echo "⬇️ Pobieram obraz Windowsa..."
  wget -O windows.raw.gz "$IMAGE_URL" || {
    echo -e "${RED}❌ Pobieranie obrazu nie powiodło się${NC}"
    exit 1
  }
fi

# 💽 Wgrywanie obrazu
echo "💿 Wgrywanie obrazu na /dev/$DESTINATION_DEVICE..."
pigz -dc windows.raw.gz | dd of=/dev/$DESTINATION_DEVICE bs=4M status=progress oflag=direct || {
  echo -e "${RED}❌ Zapis dd nie powiódł się${NC}"
  exit 1
}

sync

# 🧹 Czyszczenie pliku obrazu (opcjonalnie)
# echo "🧹 Usuwam plik obrazu windows.raw.gz..."
# rm -f windows.raw.gz
# sync

# ✅ Podsumowanie
echo "📋 Podsumowanie instalacji:"
fdisk -l /dev/$DESTINATION_DEVICE || {
  echo -e "${RED}❌ Nie udało się wyświetlić tabeli partycji${NC}"
  exit 1
}

echo -e "${GREEN}✅ Gotowe! Windows powinien być zainstalowany na /dev/$DESTINATION_DEVICE${NC}"
echo "📌 Zrestartuj instancję i spróbuj połączyć się przez RDP (jeśli obraz obsługuje RDP)."
