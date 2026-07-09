#!/bin/bash
# post_task hook for organize_downloads_by_type on Finder/macOS.
#
# Produces /tmp/organize_downloads_by_type_result.json with:
#   - task_start (unix epoch)
#   - root_loose_files: files left in the root of ~/Downloads/ (basenames)
#   - subfolder_exists: map of {Documents,Images,Archives,Other} → bool
#   - subfolder_contents: map of folder → list of basenames inside
#   - expected_in_correct_folder: per-file bool for each of the 8 expected files
#   - extra_folders: any folders in ~/Downloads/ that are NOT one of the 4 expected
#   - sentinel_seed_present: true if at least one seeded file (by name) is still
#       anywhere in ~/Downloads — guards against the "all files vanished" case
#       (per Anti-Pattern #9, an absence-trivially-true scenario)
#
# Anti-Pattern #12: the Python heredoc has try/except around its main logic
# and writes a safe default if anything fails, so the verifier always reads
# valid JSON.

set -u   # NOT set -e — we want to continue and emit a result JSON even on
         # partial failure.

echo "=== Exporting organize_downloads_by_type results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

DOWNLOADS="$HOME/Downloads"

# All filesystem analysis in one Python pass so JSON quoting is right.
# Safe default written to RESULT_JSON if Python raises.
RESULT_JSON='{"task_start": 0, "root_loose_files": [], "subfolder_exists": {}, "subfolder_contents": {}, "expected_in_correct_folder": {}, "extra_folders": [], "sentinel_seed_present": false, "export_error": "init"}'

RESULT_JSON=$(/usr/bin/python3 - "$DOWNLOADS" "$TASK_START" << 'PYEOF'
import json
import os
import sys

DOWNLOADS = sys.argv[1]
TASK_START = int(sys.argv[2])

EXPECTED_FOLDERS = ["Documents", "Images", "Archives", "Other"]
EXPECTED_PLACEMENT = {
    "Documents": ["reading_list.pdf", "meeting_notes.txt"],
    "Images":    ["wallpaper.jpg", "screenshot.png"],
    "Archives":  ["backup.zip", "data.tar.gz"],
    "Other":     ["playlist.m3u", "route_planning.gpx"],
}
ALL_SEED_NAMES = [name for files in EXPECTED_PLACEMENT.values() for name in files]

result = {
    "task_start": TASK_START,
    "root_loose_files": [],
    "subfolder_exists": {f: False for f in EXPECTED_FOLDERS},
    "subfolder_contents": {f: [] for f in EXPECTED_FOLDERS},
    "expected_in_correct_folder": {name: False for name in ALL_SEED_NAMES},
    "extra_folders": [],
    "sentinel_seed_present": False,
}

try:
    # Files at root (depth 1, type=file only) — agent should leave none here.
    for entry in sorted(os.listdir(DOWNLOADS)):
        full = os.path.join(DOWNLOADS, entry)
        if os.path.isfile(full):
            if entry == ".DS_Store":
                # .DS_Store is a Finder-managed dotfile, not an agent artifact.
                # Doesn't count as a "loose file" the agent failed to move.
                continue
            result["root_loose_files"].append(entry)
        elif os.path.isdir(full):
            if entry in EXPECTED_FOLDERS:
                result["subfolder_exists"][entry] = True
                # List the basenames inside (depth 1)
                try:
                    inner = sorted(
                        e for e in os.listdir(full)
                        if os.path.isfile(os.path.join(full, e)) and e != ".DS_Store"
                    )
                except OSError:
                    inner = []
                result["subfolder_contents"][entry] = inner
            else:
                result["extra_folders"].append(entry)

    # Walk the entire ~/Downloads tree once to check the per-file
    # "correct location" map. A file is "in its correct folder" iff it
    # appears at ~/Downloads/<expected_folder>/<filename>.
    for folder, expected_files in EXPECTED_PLACEMENT.items():
        for fname in expected_files:
            target = os.path.join(DOWNLOADS, folder, fname)
            if os.path.isfile(target):
                result["expected_in_correct_folder"][fname] = True

    # Sentinel: is ANY seeded file still present anywhere in the tree?
    # Used to detect the "agent deleted everything" gaming attempt; if the
    # 8 seed files all vanished, that's not a successful organization.
    found_anywhere = False
    for dirpath, _dnames, fnames in os.walk(DOWNLOADS):
        for f in fnames:
            if f in ALL_SEED_NAMES:
                found_anywhere = True; break
        if found_anywhere:
            break
    result["sentinel_seed_present"] = found_anywhere

except Exception as exc:
    result["export_error"] = f"{type(exc).__name__}: {exc}"

print(json.dumps(result, indent=2))
PYEOF
)

echo "$RESULT_JSON" > /tmp/organize_downloads_by_type_result.json
echo "$RESULT_JSON"

echo "=== Export complete ==="
