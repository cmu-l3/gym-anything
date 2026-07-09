#!/bin/bash
# Export: raycast_hotkey_conflict_modifiers

set -euo pipefail
echo "=== Export: raycast_hotkey_conflict_modifiers ==="

RESULT_FILE="/tmp/raycast_hotkey_conflict_modifiers_result.json"
START_TS=$(cat /tmp/raycast_hotkey_conflict_modifiers_start_ts 2>/dev/null || echo "0")
INITIAL_HOTKEY=$(cat /tmp/raycast_hotkey_conflict_modifiers_hotkey64_initial 2>/dev/null || echo "")
INITIAL_WAL=$(cat /tmp/raycast_hotkey_conflict_modifiers_wal_initial 2>/dev/null || echo "0")
EXPORT_FILE="/Users/lume/Desktop/raycast_hotkey_export.rayconfig"

# --- 1. Read current macOS hotkey 64 ---
CURRENT_HOTKEY_64=$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null | grep -A4 "    64 =" | tr -d '\n ' || echo "")

# --- 2. Raycast WAL delta ---
RAYCAST_DB_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-enc.sqlite-wal"
CURRENT_WAL_SIZE=$(stat -f%z "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")
WAL_MTIME=$(stat -f%m "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")

# --- 3. Rayconfig export ---
EXPORT_EXISTS="false"
EXPORT_NEW="false"
EXPORT_SIZE="0"
EXPORT_CONTENT_PREVIEW=""
if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_MTIME=$(stat -f%m "$EXPORT_FILE" 2>/dev/null || echo "0")
    EXPORT_SIZE=$(stat -f%z "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$EXPORT_MTIME" -gt "$START_TS" ]; then EXPORT_NEW="true"; fi
    # rayconfig is gzip-compressed JSON when export password is empty
    EXPORT_CONTENT_PREVIEW=$(gzip --decompress --keep --suffix .rayconfig --stdout "$EXPORT_FILE" 2>/dev/null | head -c 4000 || echo "")
fi

# --- 4. Assemble ---
export INITIAL_HOTKEY_ENV="$INITIAL_HOTKEY"
export CURRENT_HOTKEY_ENV="$CURRENT_HOTKEY_64"
export EXPORT_CONTENT_PREVIEW_ENV="$EXPORT_CONTENT_PREVIEW"

python3 - "$RESULT_FILE" "$START_TS" "$INITIAL_WAL" "$CURRENT_WAL_SIZE" "$WAL_MTIME" "$EXPORT_EXISTS" "$EXPORT_NEW" "$EXPORT_SIZE" << 'PYEOF'
import json, os, sys

result_file, start_ts, initial_wal, current_wal, wal_mtime, export_exists, export_new, export_size = sys.argv[1:9]
initial_hotkey = os.environ.get("INITIAL_HOTKEY_ENV", "")
current_hotkey = os.environ.get("CURRENT_HOTKEY_ENV", "")
export_preview = os.environ.get("EXPORT_CONTENT_PREVIEW_ENV", "")

result = {
    "task_start":                  int(start_ts),
    "initial_macos_hotkey_64":     initial_hotkey,
    "current_macos_hotkey_64":     current_hotkey,
    "macos_hotkey_64_unchanged":   initial_hotkey == current_hotkey and bool(initial_hotkey),
    "wal_size_initial":            int(initial_wal),
    "wal_size_current":            int(current_wal),
    "wal_size_delta":              int(current_wal) - int(initial_wal),
    "wal_mtime":                   int(wal_mtime),
    "wal_changed_after_setup":     int(wal_mtime) > int(start_ts),
    "export_file_exists":          export_exists.strip() == "true",
    "export_file_is_new":          export_new.strip() == "true",
    "export_file_size_bytes":      int(export_size),
    "export_content_preview":      export_preview,
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"WROTE {result_file}: hotkey_unchanged={result['macos_hotkey_64_unchanged']} "
      f"wal_delta={result['wal_size_delta']} export_exists={result['export_file_exists']}")
PYEOF

echo "=== Export complete ==="
