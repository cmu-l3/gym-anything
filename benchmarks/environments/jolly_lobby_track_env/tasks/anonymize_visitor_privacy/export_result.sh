#!/bin/bash
echo "=== Exporting Anonymize Visitor Privacy Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/anonymize_visitor_privacy_start_time 2>/dev/null || echo "0")

# ============================================================
# 1. Capture Database State
# ============================================================
# We need to check if the database contains the "Redacted" strings.
# Since we can't easily query Access/SDF on Linux without specific tools,
# we will use 'strings' to extract text data from the binary DB file.

DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null | head -1)
DB_MODIFIED="false"
STRINGS_FOUND="false"

if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
    echo "Analyzing database file: $DB_FILE"
    
    # Check modification time
    DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # Extract strings for verification
    # We look for the specific anonymized values
    strings "$DB_FILE" | grep -iE "Redacted|Privacy Request|Marcus Vane" > /tmp/db_strings_extract.txt
    
    # Check if file size is reasonable
    DB_SIZE=$(stat -c %s "$DB_FILE")
else
    echo "WARNING: Database file not found for analysis"
    echo "" > /tmp/db_strings_extract.txt
    DB_SIZE=0
fi

# ============================================================
# 2. Check for App State
# ============================================================
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# ============================================================
# 3. Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Read extracted strings into a JSON-safe format (simple list check)
HAS_REDACTED=$(grep -iq "Redacted" /tmp/db_strings_extract.txt && echo "true" || echo "false")
HAS_PRIVACY=$(grep -iq "Privacy Request" /tmp/db_strings_extract.txt && echo "true" || echo "false")
HAS_ORIGINAL=$(grep -iq "Marcus Vane" /tmp/db_strings_extract.txt && echo "true" || echo "false")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_modified": $DB_MODIFIED,
    "db_size_bytes": $DB_SIZE,
    "app_running": $APP_RUNNING,
    "strings_check": {
        "has_redacted": $HAS_REDACTED,
        "has_privacy_request": $HAS_PRIVACY,
        "has_original_name": $HAS_ORIGINAL
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="