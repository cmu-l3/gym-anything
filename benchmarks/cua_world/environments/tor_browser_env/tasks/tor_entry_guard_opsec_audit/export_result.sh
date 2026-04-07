#!/bin/bash
# export_result.sh for tor_entry_guard_opsec_audit task
set -e

echo "=== Exporting tor_entry_guard_opsec_audit results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if output file exists and read it
OUTPUT_FILE="/home/ga/Documents/guard_audit.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME="0"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | head -c 5000) # Read up to 5KB to prevent bloat
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

# 3. Locate Tor state file and copy for Python script
STATE_FILE_COPIED="false"
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Tor/state" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Tor/state" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Tor/state"
do
    if [ -f "$candidate" ]; then
        cp "$candidate" "/tmp/tor_state_copy"
        STATE_FILE_COPIED="true"
        echo "Found Tor state file: $candidate"
        break
    fi
done

# 4. Locate Tor places.sqlite and copy for Python script
PLACES_DB_COPIED="false"
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/places.sqlite" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/places.sqlite" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/places.sqlite"
do
    if [ -f "$candidate" ]; then
        cp "$candidate" "/tmp/places_copy.sqlite" 2>/dev/null || true
        [ -f "${candidate}-wal" ] && cp "${candidate}-wal" "/tmp/places_copy.sqlite-wal" 2>/dev/null || true
        [ -f "${candidate}-shm" ] && cp "${candidate}-shm" "/tmp/places_copy.sqlite-shm" 2>/dev/null || true
        PLACES_DB_COPIED="true"
        echo "Found places.sqlite: $candidate"
        break
    fi
done

# 5. Execute Python script to safely parse DB, State file, and construct JSON
python3 << 'PYEOF' > /tmp/task_result.json
import json
import sqlite3
import os
import re

result = {
    "file_exists": "$FILE_EXISTS" == "true",
    "file_mtime": int("$FILE_MTIME"),
    "task_start_time": int("$TASK_START"),
    "file_content": """$FILE_CONTENT""",
    "valid_guard_fingerprints": [],
    "history_visited_metrics": False,
    "error": None
}

# Parse Tor state file for Guard fingerprints
if os.path.exists("/tmp/tor_state_copy"):
    try:
        with open("/tmp/tor_state_copy", "r") as f:
            content = f.read()
        # Find 40-character hex strings associated with Guard entries
        # Format usually involves lines starting with "Guard " or "EntryGuard "
        valid_fps = set()
        for line in content.split('\n'):
            if line.startswith('Guard ') or line.startswith('EntryGuard '):
                # Extract 40-char hex
                match = re.search(r'\b([A-Fa-f0-9]{40})\b', line)
                if match:
                    valid_fps.add(match.group(1).upper())
        result["valid_guard_fingerprints"] = list(valid_fps)
    except Exception as e:
        result["error"] = f"Failed parsing state file: {str(e)}"

# Parse places.sqlite for metrics.torproject.org visits
if os.path.exists("/tmp/places_copy.sqlite"):
    try:
        conn = sqlite3.connect("/tmp/places_copy.sqlite")
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places WHERE url LIKE '%metrics.torproject.org/rs%'")
        if c.fetchone():
            result["history_visited_metrics"] = True
        conn.close()
    except Exception as e:
        # Don't overwrite state file error if exists
        result["error"] = result.get("error") or f"Failed querying history: {str(e)}"

print(json.dumps(result, indent=2))
PYEOF

# Clean up temporary DB and state copies
rm -f /tmp/tor_state_copy /tmp/places_copy.sqlite* 2>/dev/null || true

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/task_result.json