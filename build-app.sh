#!/bin/sh
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
build_root="${YA7_BUILD_ROOT:-$project_dir/../../work/XcodeBuild}"
output_path="${1:-$project_dir/../YA7.app}"
stage_path="$build_root/Export/YA7.app"
signing_identity="${YA7_SIGNING_IDENTITY:-${ARCHIV_SIGNING_IDENTITY:--}}"
signing_flags=--timestamp
if [ "$signing_identity" = - ]; then signing_flags=--timestamp=none; fi

xcodebuild -project "$project_dir/YA7.xcodeproj" -scheme YA7 \
    -configuration Release -derivedDataPath "$build_root" \
    -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="$signing_identity" DEVELOPMENT_TEAM="${YA7_DEVELOPMENT_TEAM:-}" \
    OTHER_CODE_SIGN_FLAGS="$signing_flags" build

mkdir -p "$build_root/Export"
if [ -d "$stage_path" ]; then rm -rf "$stage_path"; fi
ditto "$build_root/Build/Products/Release/YA7.app" "$stage_path"
codesign --verify --deep --strict "$stage_path"
if [ -e "$output_path" ]; then
    previous_path="$build_root/Previous-$(date +%Y%m%d-%H%M%S).app"
    mv "$output_path" "$previous_path"
fi
mkdir -p "$(dirname "$output_path")"
ditto "$stage_path" "$output_path"
codesign --verify --deep --strict "$output_path"
printf 'Mac-App mit drei Finder-Schnellaktionen erstellt: %s\n' "$output_path"
