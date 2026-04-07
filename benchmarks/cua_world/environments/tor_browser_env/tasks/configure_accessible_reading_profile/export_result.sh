#!/bin/bash
# export_result.sh - Post-task hook for configure_accessible_reading_profile task
# Exports preferences and history database for verification

echo "=== Exporting configure_accessible_reading_profile task results ==="

TASK_NAME="configure_accessible_reading_profile"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START_TIMESTAMP=$(cat /tmp/${TASK_NAME}_start_timestamp 2>/dev/null || echo "0")

# Find Tor Browser profile directory
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

PREFS_FILE="$PROFILE_DIR/prefs.js"
PLACES_DB="$PROFILE_DIR/places.sqlite"

# Check modification time of prefs.js
PREFS_MTIME=0
if [ -f "$PREFS_FILE" ]; then
    PREFS_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
fi

# Create safe copies of databases to avoid WAL locks
TEMP_DB="/tmp/${TASK_NAME}_places_export.sqlite"
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Extract and process data using Python
python3 << PYEOF
import json
import os
import sqlite3

result = {
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "prefs_mtime": $PREFS_MTIME,
    "prefs_file_exists": os.path.exists("$PREFS_FILE"),
    "extracted_prefs": {},
    "history_has_check_torproject": False,
    "check_torproject_visit_after_start": False
}

# 1. Parse prefs.js
if result["prefs_file_exists"]:
    with open("$PREFS_FILE", "r") as f:
        for line in f:
            if line.strip().startswith("user_pref("):
                parts = line.split(",", 1)
                if len(parts) == 2:
                    key = parts[0].split('"')[1] if '"' in parts[0] else ""
                    val_str = parts[1].rsplit(')', 1)[0].strip()
                    
                    if not key:
                        continue
                        
                    # Target preferences to parse
                    target_keys = [
                        "font.minimum-size.x-western",
                        "browser.display.document_color_use",
                        "browser.display.foreground_color",
                        "browser.display.background_color",
                        "browser.anchor_color",
                        "browser.display.use_document_fonts",
                        "accessibility.browsewithcaret"
                    ]
                    
                    if key in target_keys:
                        if val_str.startswith('"'):
                            result["extracted_prefs"][key] = val_str.strip('"')
                        elif val_str == "true":
                            result["extracted_prefs"][key] = True
                        elif val_str == "false":
                            result["extracted_prefs"][key] = False
                        else:
                            try:
                                result["extracted_prefs"][key] = int(val_str)
                            except ValueError:
                                result["extracted_prefs"][key] = val_str

# 2. Check places.sqlite for history
db_path = "$TEMP_DB"
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        # Check for check.torproject.org
        c.execute("""
            SELECT p.url, MAX(h.visit_date) as last_visit
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            WHERE LOWER(p.url) LIKE '%check.torproject.org%'
            GROUP BY p.id
            ORDER BY last_visit DESC
            LIMIT 1
        """)
        row = c.fetchone()
        if row:
            result["history_has_check_torproject"] = True
            visit_date_sec = row["last_visit"] / 1000000  # Microseconds to seconds
            if visit_date_sec > $TASK_START_TIMESTAMP:
                result["check_torproject_visit_after_start"] = True
                
        conn.close()
    except Exception as e:
        result["db_error"] = str(e)

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Cleanup temp db
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json