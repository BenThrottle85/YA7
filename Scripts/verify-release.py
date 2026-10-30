#!/usr/bin/env python3
"""Read-only preflight. Local structural success is not notarization approval."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('--team-id')
parser.add_argument('--allow-local', action='store_true', help='Check structure only; allow ad-hoc signatures without timestamps.')
parser.add_argument('--report', type=Path)
args = parser.parse_args()
app = args.app.resolve()
errors = []
records = []
environment = dict(os.environ, LC_ALL='C', LANG='C')

def command(arguments):
    return subprocess.run(arguments, capture_output=True, env=environment)

if args.team_id and not re.fullmatch(r'[A-Z0-9]{10}', args.team_id):
    parser.error('Team ID must contain exactly 10 uppercase letters/digits.')
if not (app / 'Contents/Info.plist').is_file():
    parser.error('App bundle not found.')

verification = command(['codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app)])
if verification.returncode:
    errors.append('Bundle signature verification failed: ' + verification.stderr.decode(errors='replace').strip())

magic = {bytes.fromhex(value) for value in ['feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']}
executables = []
for file in sorted(app.rglob('*')):
    if file.is_file() and not file.is_symlink():
        with file.open('rb') as stream:
            if stream.read(4) in magic:
                executables.append(file)
if not executables:
    errors.append('No Mach-O code found.')

for file in executables:
    relative = str(file.relative_to(app))
    architectures = command(['lipo', '-archs', str(file)]).stdout.decode().split()
    if set(architectures) != {'arm64', 'x86_64'}:
        errors.append(relative + ': expected arm64 and x86_64.')
    if not args.allow_local:
        trusted = command(['codesign', '--verify', '--strict', '-R', '=anchor apple generic', str(file)])
        if trusted.returncode:
            errors.append(relative + ': signature is not anchored to Apple.')
    for arch in architectures:
        display = command(['codesign', '--display', '--verbose=4', '--arch', arch, str(file)])
        details = (display.stdout + display.stderr).decode(errors='replace')
        entitlements = command(['codesign', '--display', '--entitlements', '-', '--xml', '--arch', arch, str(file)])
        data = entitlements.stdout
        start = data.find(b'<?xml')
        if start >= 0:
            end = data.find(b'</plist>', start)
            values = plistlib.loads(data[start:end + len(b'</plist>')])
        else:
            values = {}
        team_match = re.search(r'^TeamIdentifier=(.+)$', details, re.MULTILINE)
        team = team_match.group(1).strip() if team_match else None
        hardened = bool(re.search(r'^CodeDirectory .*\bruntime\b', details, re.MULTILINE))
        timestamped = bool(re.search(r'^Timestamp=', details, re.MULTILINE))
        developer_id = bool(re.search(r'^Authority=Developer ID Application:', details, re.MULTILINE))
        debug = bool(values.get('com.apple.security.get-task-allow', False))
        record = dict(path=relative, architecture=arch, hardened_runtime=hardened, secure_timestamp=timestamped,
                      developer_id=developer_id, team_id=team, get_task_allow=debug)
        records.append(record)
        prefix = relative + ' [' + arch + ']: '
        if display.returncode or entitlements.returncode:
            errors.append(prefix + 'could not read signature or entitlements.')
        if not hardened:
            errors.append(prefix + 'Hardened Runtime missing.')
        if debug:
            errors.append(prefix + 'get-task-allow must not be enabled in a release.')
        if not args.allow_local:
            if not developer_id:
                errors.append(prefix + 'Developer ID Application signature missing.')
            if not timestamped:
                errors.append(prefix + 'secure timestamp missing.')
            if not team or team == 'not set':
                errors.append(prefix + 'Team ID missing.')
            if args.team_id and team != args.team_id:
                errors.append(prefix + 'Team ID does not match the requested team.')

teams = {row['team_id'] for row in records if row['team_id'] and row['team_id'] != 'not set'}
if len(teams) > 1:
    errors.append('Nested components have different Team IDs.')

legal = app / 'Contents/Resources/Legal'
for name in ['NOTICE.txt', 'LGPL-2.1.txt', '7zip-License.txt', '7z2605-src.tar.xz', 'Source-Provenance.json']:
    if not (legal / name).is_file():
        errors.append('Legal resource missing: ' + name)
if (legal / 'Source-Provenance.json').is_file() and (legal / '7z2605-src.tar.xz').is_file():
    provenance = json.loads((legal / 'Source-Provenance.json').read_text())
    source = next(row for row in provenance['archives'] if row['filename'] == '7z2605-src.tar.xz')
    if hashlib.sha256((legal / source['filename']).read_bytes()).hexdigest() != source['sha256']:
        errors.append('Bundled upstream source checksum mismatch.')

report = dict(mode='local-structure-only' if args.allow_local else 'developer-id-required',
              passed=not errors, apple_notarization_status='not checked by this tool',
              executable_count=len(executables), architecture_records=records, errors=errors)
formatted = json.dumps(report, indent=2) + '\n'
if args.report:
    args.report.write_text(formatted)
print(formatted)
sys.exit(1 if errors else 0)
