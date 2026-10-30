#!/bin/sh
# Only publishes a final output after Apple accepts it and ticket/policy checks pass.
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
app_path="${1:-$project_dir/../YA7.app}"
: "${YA7_SIGNING_IDENTITY:?Set your Developer ID Application signing identity.}"
: "${YA7_DEVELOPMENT_TEAM:?Set your 10-character Apple Team ID.}"
: "${YA7_NOTARY_PROFILE:?Set an existing notarytool keychain profile; never put passwords in this script.}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
output_path="${2:-$project_dir/../YA7-$version-macOS.dmg}"
if [ -e "$output_path" ]; then
    printf 'Output already exists: %s\n' "$output_path" >&2
    exit 1
fi
work_root="${YA7_WORK_ROOT:-$project_dir/../../work}"
mkdir -p "$work_root"
stage_root="$(mktemp -d "$work_root/YA7-notary.XXXXXX")"
python3 "$project_dir/Scripts/verify-release.py" "$app_path" --team-id "$YA7_DEVELOPMENT_TEAM" --report "$stage_root/preflight.json"
image_path="$stage_root/YA7-$version-macOS.dmg"
sh "$project_dir/Scripts/build-dmg.sh" "$app_path" "$image_path"
codesign --force --sign "$YA7_SIGNING_IDENTITY" --timestamp "$image_path"
codesign --verify --strict -R '=anchor apple generic' "$image_path"
submit_exit=0
xcrun notarytool submit "$image_path" --keychain-profile "$YA7_NOTARY_PROFILE" --wait --output-format json > "$stage_root/submission.json" || submit_exit=$?
status="$(python3 - "$stage_root/submission.json" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1])); print(data.get('status', 'Unknown'))
except (ValueError, OSError):
    print('Unknown')
PY
)"
submission_id="$(python3 - "$stage_root/submission.json" <<'PY'
import json, sys, uuid
try:
    data = json.load(open(sys.argv[1])); print(uuid.UUID(data['id']))
except (KeyError, ValueError, OSError):
    pass
PY
)"
if [ -n "$submission_id" ]; then
    xcrun notarytool log "$submission_id" --keychain-profile "$YA7_NOTARY_PROFILE" "$stage_root/notary-log.json"
fi
if [ "$submit_exit" -ne 0 ] || [ "$status" != Accepted ]; then
    printf 'Apple did not accept this submission (status: %s). Logs: %s\n' "$status" "$stage_root" >&2
    exit 1
fi
python3 - "$stage_root/notary-log.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
issues = data.get('issues') or []
if issues:
    print('Notary log contains findings requiring review:', file=sys.stderr)
    for issue in issues:
        print(issue.get('severity'), issue.get('path'), issue.get('message'), file=sys.stderr)
    sys.exit(1)
PY
xcrun stapler staple "$image_path"
xcrun stapler validate "$image_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$image_path"
hdiutil verify "$image_path"
mkdir -p "$(dirname -- "$output_path")"
mv "$image_path" "$output_path"
/usr/bin/shasum -a 256 "$output_path" > "$output_path.sha256"
printf 'Apple accepted and ticket validated: %s\nNotary log: %s\n' "$output_path" "$stage_root/notary-log.json"
