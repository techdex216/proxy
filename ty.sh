#!/bin/bash

if [ -z "$1" ]; then
  echo "Użycie: $0 LINK_DO_YOUTUBE"
  exit 1
fi

URL="$1"
FILE="video_$(date +%s).mp4"

echo "Pobieram film z YouTube..."
yt-dlp -f bestvideo+bestaudio --merge-output-format mp4 "$URL" -o "$FILE"
if [ $? -ne 0 ]; then
  echo "Błąd pobierania filmu."
  exit 1
fi

echo "Wysyłam plik na transfer.sh..."
UPLOAD_LINK=$(curl --upload-file "$FILE" https://transfer.sh/"$FILE")

if [[ "$UPLOAD_LINK" == http* ]]; then
  echo "Plik został wysłany!"
  echo "Link do pobrania:"
  echo "$UPLOAD_LINK"
else
  echo "Coś poszło nie tak przy uploadzie:"
  echo "$UPLOAD_LINK"
  exit 1
fi

# Opcjonalnie usuń lokalny plik
rm "$FILE"
