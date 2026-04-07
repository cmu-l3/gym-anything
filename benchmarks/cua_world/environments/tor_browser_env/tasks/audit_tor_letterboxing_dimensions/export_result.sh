#!/bin/bash
# export_result.sh for audit_tor_letterboxing_dimensions
# Captures prefs.js, audit file contents, and history data

echo "=== Exporting audit_tor_letterboxing_dimensions results ==="

TASK_NAME="audit_tor_letterboxing_dimensions"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Find Tor Browser profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# Check prefs.js for letterboxing config
PREFS_FILE="$PROFILE_DIR/prefs.js"
LETTERBOXING_FALSE="false"

if [ -f "$PREFS_FILE" ]; then
    if grep -q 'user_pref("privacy\.resistFingerprinting\.letterboxing", false);' "$PREFS_FILE" 2>/dev/null; then
        LETTERBOXING_FALSE="true"
    fi
fi

# Check text file
TARGET_FILE="/home/ga/Documents/letterboxing_audit.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_IS_NEW="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$TARGET_FILE" | head -n 20) # Grab up to 20 lines
    
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
fi

# Copy DB safely
PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
fi

# Query history
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/audit_tor_letterboxing_dimensions_places.sqlite"
result = {"history_has_check_torproject": False}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places WHERE url LIKE '%check.torproject.org%'")
        if c.fetchone():
            result["history_has_check_torproject"] = True
        conn.close()
    except Exception:
        pass

with open("/tmp/db_check_temp.json", "w") as f:
    json.dump(result, f)
PYEOF

HISTORY_CHECK=$(cat /tmp/db_check_temp.json 2>/dev/null || echo '{"history_has_check_torproject": false}')

# Combine results into final JSON
python3 << PYEOF2
import json

try:
    history_data = json.loads('''$HISTORY_CHECK''')
except:
    history_data = {"history_has_check_torproject": False}

result = {
    "task": "$TASK_NAME",
    "letterboxing_false_in_prefs": $LETTERBOXING_FALSE,
    "audit_file_exists": $FILE_EXISTS,
    "audit_file_is_new": $FILE_IS_NEW,
    "audit_file_content": """$FILE_CONTENT""",
    "history_has_check_torproject": history_data.get("history_has_check_torproject", False),
    "task_start_timestamp": $TASK_START
}

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" /tmp/db_check_temp.json /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="