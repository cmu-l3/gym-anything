#!/bin/bash
set -e

echo "=== Exporting add_visitor_photo results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check for new photo files in Lobby Track directory
# Lobby Track typically stores photos in a "Photos" subdirectory of its data folder
# We search the entire Wine prefix for new JPGs to be robust against install location variations
echo "Searching for new photo files..."
PHOTO_FOUND="false"
PHOTO_FILE_PATH=""
PHOTO_TIMESTAMP="0"

# Find paths that look like Lobby Track photo storage
# We look for files modified AFTER task start
find /home/ga/.wine/drive_c -name "*.jpg" -newermt "@$TASK_START" 2>/dev/null | while read f; do
    # Filter out the source file itself
    if [[ "$f" != *"/Documents/"* ]] && [[ "$f" != *"/temp/"* ]]; then
        echo "Found new photo candidate: $f"
        # Check if it's likely a database photo (often numeric or UUID filenames)
        # or matches the name
        echo "$f" > /tmp/found_photo_path.txt
        break
    fi
done

if [ -f /tmp/found_photo_path.txt ]; then
    PHOTO_FOUND="true"
    PHOTO_FILE_PATH=$(cat /tmp/found_photo_path.txt)
    PHOTO_TIMESTAMP=$(stat -c %Y "$PHOTO_FILE_PATH")
fi

# 2. Check for Database modification
# We check if the main database file (usually .mdb or .sdf) has been modified
DB_MODIFIED="false"
DB_PATH=""

# Common locations for Lobby Track DB
POSSIBLE_DBS=$(find /home/ga/.wine/drive_c -iname "*.mdb" -o -iname "*.sdf" -o -iname "LobbyTrack.db" 2>/dev/null)

for db in $POSSIBLE_DBS; do
    DB_MTIME=$(stat -c %Y "$db" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
        DB_PATH="$db"
        echo "Database modified: $db"
        break
    fi
done

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "photo_found": $PHOTO_FOUND,
    "photo_file_path": "$PHOTO_FILE_PATH",
    "photo_timestamp": $PHOTO_TIMESTAMP,
    "db_modified": $DB_MODIFIED,
    "db_path": "$DB_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="