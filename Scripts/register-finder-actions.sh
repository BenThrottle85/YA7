#!/bin/sh
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
app_path="${1:-$project_dir/../YA7.app}"
codesign --verify --deep --strict "$app_path"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path"
for action in PackAction ExtractAction CheckAction; do
    /usr/bin/pluginkit -a "$app_path/Contents/PlugIns/$action.appex"
done
for action in pack extract check; do
    /usr/bin/pluginkit -e use -i "de.local.archiv.prototype.$action"
done
printf 'Registriert. Im Finder: Rechtsklick → Schnellaktionen → Anpassen … und die drei YA7-Aktionen aktivieren.\n'
