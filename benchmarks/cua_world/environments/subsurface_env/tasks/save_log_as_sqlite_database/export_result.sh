#!/bin/bash
set -e
echo "=== Exporting task results ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/dives_database.sqlite"

# Check if output file was created
OUTPUT_EXISTS="false"
OUTPUT_MTIME=0
OUTPUT_SIZE=0
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
fi

# Check if original XML file still exists (anti-gaming: agent shouldn't have overwritten it)
ORIGINAL_EXISTS="false"
if [ -f "/home/ga/Documents/dives.ssrf" ]; then
    ORIGINAL_EXISTS="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run python script to deeply verify SQLite contents
# This uses python's built-in sqlite3 to guarantee the file is actually a relational database
SQLITE_CHECK_JSON=$(python3 << 'EOF'
import sqlite3
import json
import os

db_path = "/home/ga/Documents/dives_database.sqlite"
res = {"is_valid_db": False, "has_dives_table": False, "dive_count": 0, "error": None}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        # Verify schema
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='dives'")
        if cursor.fetchone():
            res["has_dives_table"] = True
            # Verify data
            cursor.execute("SELECT COUNT(*) FROM dives")
            res["dive_count"] = cursor.fetchone()[0]
            res["is_valid_db"] = True
        else:
            # Check if it's a valid SQLite DB but empty/different schema
            cursor.execute("SELECT name FROM sqlite_master")
            cursor.fetchall()
            res["is_valid_db"] = True
        conn.close()
    except Exception as e:
        res["error"] = str(e)

print(json.dumps(res))
EOF
)

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_mtime": $OUTPUT_MTIME,
    "output_size_bytes": $OUTPUT_SIZE,
    "original_exists": $ORIGINAL_EXISTS,
    "sqlite_check": $SQLITE_CHECK_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely with guaranteed permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="