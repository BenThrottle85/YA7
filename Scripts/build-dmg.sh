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
    *"Authority=Developer ID Application:"*) signing_note='Signed with Developer ID. macOS checks Apple notarization when opening the image.' ;;
    *) signing_note='Local development build. Not notarized.' ;;
esac
mkdir -p "$stage_root/Payload"
ditto "$app_path" "$stage_root/Payload/YA7.app"
ln -s /Applications "$stage_root/Payload/Applications"
touch "$stage_root/Payload/.metadata_never_index"
cp "$app_path/Contents/Resources/Legal/NOTICE.txt" "$stage_root/Payload/THIRD-PARTY-NOTICES.txt"
cp "$app_path/Contents/Resources/Legal/YA7-License.txt" "$stage_root/Payload/LICENSE"
cp "$app_path/Contents/Resources/Legal/YA7-Licensing.md" "$stage_root/Payload/LICENSING.md"
cat > "$stage_root/Payload/Installation.txt" <<TEXT
YA7 $version - macOS 14 or later
Yet Another 7-Zip GUI for macOS

1. Drag YA7.app to Applications.
2. Eject this image and open YA7 from Applications.

English and German are supported. YA7 follows your macOS app-language
preferences; English is the fallback. To override the language, use
System Settings > General > Language & Region > Applications.

Finder: Right-click > Quick Actions > Customize.
Enable YA7: Compress, YA7: Extract and YA7: Test.
7-Zip is included. No additional installation is needed.
$signing_note

Licenses and source: YA7 > Licenses and source code...
The app contains license texts and the matching 7-Zip source archive.
YA7 source and build scripts: https://github.com/BenThrottle85/YA7

Deutsch
1. YA7.app auf Applications (Programme) ziehen.
2. Image auswerfen und YA7 aus Programme starten.
Die Sprache folgt den macOS-App-Spracheinstellungen; Englisch ist die
Rueckfallsprache. Finder: Rechtsklick > Schnellaktionen > Anpassen.
YA7: Packen, YA7: Entpacken und YA7: Pruefen aktivieren.
Lizenzen: YA7 > Lizenzen und Quellcode ...
TEXT
hdiutil create -volname "YA7 $version" -fs HFS+ -srcfolder "$stage_root/Payload" -format UDZO -imagekey zlib-level=9 "$stage_root/YA7.dmg"
hdiutil verify "$stage_root/YA7.dmg"
mkdir -p "$(dirname -- "$output_path")"
mv "$stage_root/YA7.dmg" "$output_path"
printf 'Disk image created: %s\n' "$output_path"
