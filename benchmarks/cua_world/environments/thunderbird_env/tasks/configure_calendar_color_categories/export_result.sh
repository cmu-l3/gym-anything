#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# Close Thunderbird gracefully so it flushes SQLite and prefs.js
su - ga -c "DISPLAY=:1 wmctrl -c 'Thunderbird'" 2>/dev/null || true
sleep 3
pkill -f thunderbird 2>/dev/null || true
sleep 2

TB_PROFILE="/home/ga/.thunderbird/default-release"
LOCAL_SQLITE="${TB_PROFILE}/calendar-data/local.sqlite"
PREFS_JS="${TB_PROFILE}/prefs.js"

rm -f /tmp/categories_dump.txt /tmp/prefs_dump.txt

# 1. Query SQLite for Events and their Categories
if [ -f "$LOCAL_SQLITE" ]; then
    # We select SUMMARY (title) and CATEGORIES properties
    sqlite3 "$LOCAL_SQLITE" "SELECT p1.value, p2.value FROM cal_properties p1 LEFT JOIN cal_properties p2 ON p1.item_id = p2.item_id AND p2.key = 'CATEGORIES' WHERE p1.key = 'SUMMARY';" > /tmp/categories_dump.txt 2>/dev/null || true
fi

# 2. Query prefs.js for Category Colors
if [ -f "$PREFS_JS" ]; then
    grep "calendar.category.color" "$PREFS_JS" > /tmp/prefs_dump.txt 2>/dev/null || true
fi

# 3. Parse data using Python and write JSON
cat << 'EOF' > /tmp/parse_exports.py
import json
import os

result = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "events": {},
    "colors": {},
    "thunderbird_ran": True
}

# Parse events from SQLite dump
if os.path.exists("/tmp/categories_dump.txt"):
    with open("/tmp/categories_dump.txt", "r") as f:
        for line in f:
            parts = line.strip().split('|')
            if len(parts) == 2:
                result["events"][parts[0]] = parts[1]
            elif len(parts) == 1:
                result["events"][parts[0]] = ""

# Parse colors from prefs.js dump
if os.path.exists("/tmp/prefs_dump.txt"):
    with open("/tmp/prefs_dump.txt", "r") as f:
        for line in f:
            # Format: user_pref("calendar.category.color.internal sync", "#0000ff");
            if '"' in line:
                parts = line.split('"')
                if len(parts) >= 4:
                    key_part = parts[1]
                    val_part = parts[3]
                    # Extract just the category name (everything after the last dot)
                    if "calendar.category.color." in key_part:
                        cat_name = key_part.replace("calendar.category.color.", "").lower()
                        result["colors"][cat_name] = val_part.lower()

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

export TASK_START TASK_END
python3 /tmp/parse_exports.py

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="