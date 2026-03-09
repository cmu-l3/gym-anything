#!/bin/bash
echo "=== Exporting configure_email_notifications result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of the desktop
take_screenshot /tmp/task_final.png

# Task-specific constants
EVIDENCE_PATH="/home/ga/.wine/drive_c/LobbyTrack/email_config_evidence.png"
TARGET_STRING="mail.acmetech.com"
TASK_START_TIME=$(cat /tmp/configure_email_notifications_start_time 2>/dev/null || echo "0")

# 1. Check for Evidence Screenshot
EVIDENCE_EXISTS="false"
if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    # Check if created AFTER task start
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START_TIME" ]; then
        EVIDENCE_VALID_TIME="true"
    else
        EVIDENCE_VALID_TIME="false"
    fi
else
    EVIDENCE_VALID_TIME="false"
fi

# 2. Check Configuration Persistence (The hard part)
# We search for the unique SMTP server string in likely config locations
echo "Searching for configuration string '$TARGET_STRING'..."

CONFIG_FOUND="false"
CONFIG_FILE_PATH=""
CONFIG_TIMESTAMP_VALID="false"

# Define search paths in Wine prefix (User data, Program data, Registry files)
SEARCH_PATHS=(
    "/home/ga/.wine/drive_c/users/ga/Local Settings/Application Data/Jolly_Technologies"
    "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies"
    "/home/ga/.wine/drive_c/Program Files/Jolly Technologies"
    "/home/ga/.wine/user.reg"
    "/home/ga/.wine/system.reg"
)

# Search specifically in text-based config files first
# We use grep recursively. 
# NOTE: We use 'grep -l' to just get filenames.
FOUND_FILES=$(grep -r -l "$TARGET_STRING" "${SEARCH_PATHS[@]}" 2>/dev/null | head -5)

if [ -n "$FOUND_FILES" ]; then
    CONFIG_FOUND="true"
    # Check the first found file for timestamp
    FIRST_FILE=$(echo "$FOUND_FILES" | head -1)
    CONFIG_FILE_PATH="$FIRST_FILE"
    
    FILE_MTIME=$(stat -c %Y "$FIRST_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        CONFIG_TIMESTAMP_VALID="true"
    fi
    echo "Found string in: $FOUND_FILES"
else
    # Fallback: Check binary files (like .sdf database) if text search failed
    # utilizing strings command
    echo "Checking binary files (SDF/DB)..."
    DB_FILES=$(find /home/ga/.wine/drive_c -name "*.sdf" -o -name "*.mdb" 2>/dev/null)
    for db in $DB_FILES; do
        if strings "$db" | grep -q "$TARGET_STRING"; then
            CONFIG_FOUND="true"
            CONFIG_FILE_PATH="$db"
            FILE_MTIME=$(stat -c %Y "$db" 2>/dev/null || echo "0")
            if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
                CONFIG_TIMESTAMP_VALID="true"
            fi
            echo "Found string in binary: $db"
            break
        fi
    done
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "evidence_screenshot_exists": $EVIDENCE_EXISTS,
    "evidence_screenshot_valid_time": $EVIDENCE_VALID_TIME,
    "config_string_found": $CONFIG_FOUND,
    "config_file_path": "$CONFIG_FILE_PATH",
    "config_timestamp_valid": $CONFIG_TIMESTAMP_VALID,
    "task_start_time": $TASK_START_TIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move files for verification
# Copy evidence screenshot to /tmp for easy access if it exists
if [ "$EVIDENCE_EXISTS" = "true" ]; then
    cp "$EVIDENCE_PATH" /tmp/evidence_screenshot.png
fi

# Save JSON result
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="