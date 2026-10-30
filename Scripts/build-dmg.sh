#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
app_path="${1:-$project_dir/../YA7.app}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
output_path="${2:-$project_dir/../YA7-$version-macOS.dmg}"
stage_root="$(mktemp -d "${TMPDIR:-/tmp}/ya7-dmg.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT HUP INT TERM

codesign --verify --deep --strict "$app_path"
signature_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"
case "$signature_details" in
    *"Authority=Developer ID Application:"*)
        signing_note='Diese Fassung ist mit Developer ID signiert. Die Apple-Beglaubigung wird von macOS beim Öffnen geprüft.' ;;
    *) signing_note='Diese Entwicklungsfassung ist lokal signiert, noch nicht notarisiert.' ;;
esac
mkdir -p "$stage_root/Payload"
ditto "$app_path" "$stage_root/Payload/YA7.app"
ln -s /Applications "$stage_root/Payload/Programme"
touch "$stage_root/Payload/.metadata_never_index"
cp "$app_path/Contents/Resources/Legal/NOTICE.txt" "$stage_root/Payload/Lizenzen.txt"
cat > "$stage_root/Payload/Installation.txt" <<EOF
YA7 $version – macOS 14 oder neuer
Yet Another 7-Zip GUI for macOS

Installation
1. YA7.app auf den Programme-Link ziehen.
2. Das Image auswerfen und YA7 aus Programme öffnen.

Finder-Schnellaktionen
Im Finder: Rechtsklick → Schnellaktionen → Anpassen …
YA7: Packen, YA7: Entpacken und YA7: Prüfen aktivieren.

7-Zip ist enthalten; keine zusätzliche Installation erforderlich.
$signing_note

Lizenzen und Quellcode
Im YA7-Menü: Lizenzen und Quellcode …
Die App enthält die Lizenztexte und den passenden 7-Zip-Quellcode.
EOF

hdiutil create -volname "YA7 $version" -fs HFS+ \
    -srcfolder "$stage_root/Payload" -format UDZO -imagekey zlib-level=9 \
    "$stage_root/YA7.dmg"
hdiutil verify "$stage_root/YA7.dmg"
mkdir -p "$(dirname -- "$output_path")"
mv "$stage_root/YA7.dmg" "$output_path"
printf 'Installationsimage erstellt: %s\n' "$output_path"
