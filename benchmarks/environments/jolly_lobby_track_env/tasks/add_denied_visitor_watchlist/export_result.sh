#!/bin/bash
echo "=== Exporting Watchlist Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Find Modified Database Files
# Lobby Track stores data in .mdb (Access) or .sdf (SQL CE).
# We look for any database file modified AFTER task start.
echo "Searching for modified database files..."
MODIFIED_DB=""
DB_OPTS=$(find /home/ga/.wine/drive_c -type f \( -name "*.mdb" -o -name "*.sdf" -o -name "*.db" \) -newermt "@$TASK_START" 2>/dev/null)

if [ -n "$DB_OPTS" ]; then
    # Pick the largest one modified, assuming it's the main DB
    MODIFIED_DB=$(echo "$DB_OPTS" | xargs ls -S | head -n 1)
    echo "Found modified DB: $MODIFIED_DB"
else
    echo "No database file modified during task."
fi

# 3. Extract Text from DB (Strings Analysis)
# Since we might not have mdb-tools installed or want to rely on specific drivers,
# we use 'strings' to dump text content. This is robust for verifying entered text
# like names and incident IDs in binary DB formats.
DB_STRINGS_FILE="/tmp/db_content_dump.txt"
if [ -n "$MODIFIED_DB" ]; then
    # Extract strings (min length 3) to a text file
    strings -n 3 -e s "$MODIFIED_DB" > "$DB_STRINGS_FILE"
    strings -n 3 -e l "$MODIFIED_DB" >> "$DB_STRINGS_FILE" # Try little-endian unicode too
else
    touch "$DB_STRINGS_FILE"
fi

# 4. Check if App is Running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" >/dev/null || pgrep -f "Lobby" >/dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "db_modified": "$MODIFIED_DB",
    "db_strings_path": "$DB_STRINGS_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."