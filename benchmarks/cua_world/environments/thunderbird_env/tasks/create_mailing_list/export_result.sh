#!/bin/bash
set -euo pipefail

echo "=== Exporting create_mailing_list task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE doing any processing
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 import -window root /tmp/task_final.png" 2>/dev/null || true

# Locate the correct profile directory
PROFILE_DIR=$(grep "Path=" /home/ga/.thunderbird/profiles.ini 2>/dev/null | grep -i "default" | cut -d= -f2 | head -n 1 || echo "default-release")
FULL_PROFILE_DIR="/home/ga/.thunderbird/$PROFILE_DIR"

ABOOK_EXISTS="false"
ABOOK_MODIFIED="false"
ABOOK_SIZE=0

# Safely copy the address book database for verifier.py
# (Thunderbird locks the DB, so we copy it to a neutral location)
rm -f /tmp/task_abook.sqlite
if [ -f "$FULL_PROFILE_DIR/abook.sqlite" ]; then
    cp "$FULL_PROFILE_DIR/abook.sqlite" /tmp/task_abook.sqlite
    chmod 666 /tmp/task_abook.sqlite
    
    ABOOK_EXISTS="true"
    ABOOK_SIZE=$(stat -c %s /tmp/task_abook.sqlite 2>/dev/null || echo "0")
    
    # Check if modified after start
    ABOOK_MTIME=$(stat -c %Y "$FULL_PROFILE_DIR/abook.sqlite" 2>/dev/null || echo "0")
    if [ "$ABOOK_MTIME" -gt "$TASK_START" ]; then
        ABOOK_MODIFIED="true"
    fi
fi

# Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Create JSON metadata result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "abook_exists": $ABOOK_EXISTS,
    "abook_modified_during_task": $ABOOK_MODIFIED,
    "abook_size_bytes": $ABOOK_SIZE,
    "app_was_running": $APP_RUNNING,
    "profile_dir": "$FULL_PROFILE_DIR"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="