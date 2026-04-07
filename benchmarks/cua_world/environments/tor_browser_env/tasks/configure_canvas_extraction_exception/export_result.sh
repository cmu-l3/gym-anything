#!/bin/bash
# export_result.sh for configure_canvas_extraction_exception
# Evaluates file outputs and Tor Browser database permissions

echo "=== Exporting Canvas Extraction Task Results ==="

TASK_NAME="configure_canvas_extraction_exception"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Check the output file
TARGET_FILE="/home/ga/Documents/OfflineTools/exported_chart.txt"
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0
BASE64_VALID="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
    
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Check if the content resembles a valid PNG data URI
    if grep -q "data:image/png;base64," "$TARGET_FILE" 2>/dev/null; then
        BASE64_VALID="true"
    fi
fi

# Extract DB state (Permissions and History)
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

PERMISSIONS_DB="$PROFILE_DIR/permissions.sqlite"
PLACES_DB="$PROFILE_DIR/places.sqlite"

# Make safe copies to avoid DB locking
TEMP_PERMS="/tmp/${TASK_NAME}_perms.sqlite"
TEMP_PLACES="/tmp/${TASK_NAME}_places.sqlite"

[ -f "$PERMISSIONS_DB" ] && cp "$PERMISSIONS_DB" "$TEMP_PERMS" 2>/dev/null || true
[ -f "$PLACES_DB" ] && cp "$PLACES_DB" "$TEMP_PLACES" 2>/dev/null || true

# Use Python to evaluate DB contents
python3 << PYEOF > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

result = {
    "canvas_permission_granted": False,
    "tool_visited_in_history": False
}

# Check permissions
if os.path.exists("$TEMP_PERMS"):
    try:
        conn = sqlite3.connect("$TEMP_PERMS")
        c = conn.cursor()
        # permission=1 means ALLOW, type is canvas/extractData
        c.execute("SELECT count(*) FROM moz_perms WHERE type='canvas/extractData' AND permission=1")
        count = c.fetchone()[0]
        if count > 0:
            result["canvas_permission_granted"] = True
        conn.close()
    except Exception as e:
        result["db_error_perms"] = str(e)

# Check history
if os.path.exists("$TEMP_PLACES"):
    try:
        conn = sqlite3.connect("$TEMP_PLACES")
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places WHERE url LIKE '%chart_tool.html%'")
        if c.fetchone() is not None:
            result["tool_visited_in_history"] = True
        conn.close()
    except Exception as e:
        result["db_error_places"] = str(e)

with open("/tmp/${TASK_NAME}_db_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Merge into final result JSON
python3 << PYEOF2
import json

try:
    with open('/tmp/${TASK_NAME}_db_result.json', 'r') as f:
        db_data = json.load(f)
except:
    db_data = {}

db_data.update({
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "base64_valid": $BASE64_VALID,
    "task_start": $TASK_START
})

with open('/tmp/task_result.json', 'w') as f:
    json.dump(db_data, f, indent=2)
PYEOF2

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_PERMS" "$TEMP_PLACES" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json