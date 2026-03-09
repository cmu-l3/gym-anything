#!/bin/bash
echo "=== Exporting configure_facility_profile results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START_FILE="/tmp/configure_facility_profile_start_time"
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application is running
APP_RUNNING="false"
if pgrep -f "LobbyTrack\|Lobby.*Track" > /dev/null; then
    APP_RUNNING="true"
fi

# --- DATA VERIFICATION ---
# Strategy: Scan likely data locations in the Wine prefix for files modified 
# AFTER the task start that contain the target strings.
# This avoids needing to know the exact proprietary database format (Access/Compact SQL/XML).

SEARCH_DIR="/home/ga/.wine/drive_c"
EXPECTED_COMPANY="Greenfield Medical Center"
EXPECTED_ADDRESS="450 Healthcare"
EXPECTED_ZIP="97201"
EXPECTED_PHONE="555-0142"

echo "Scanning for modified files containing configuration data..."

# Find files modified after start time, excluding log files and temporary caches
# We look in ProgramData, Users (Documents/AppData), and Program Files
MODIFIED_FILES=$(find "$SEARCH_DIR" -type f -newermt "@$TASK_START" \
    -not -path "*/Temp/*" \
    -not -path "*/temp/*" \
    -not -path "*/Logs/*" \
    -not -name "*.log" \
    -not -name "*.tmp" \
    2>/dev/null)

FOUND_COMPANY="false"
FOUND_ADDRESS="false"
FOUND_ZIP="false"
FOUND_PHONE="false"
CONFIG_FILE_MODIFIED="false"

# Check the modified files for the strings
# We use grep with binary support (-a) because DB files might be binary
if [ -n "$MODIFIED_FILES" ]; then
    CONFIG_FILE_MODIFIED="true"
    
    echo "Checking modified files for strings..."
    for f in $MODIFIED_FILES; do
        if grep -Faq "$EXPECTED_COMPANY" "$f"; then
            FOUND_COMPANY="true"
            echo "Found Company in: $f"
        fi
        if grep -Faq "$EXPECTED_ADDRESS" "$f"; then
            FOUND_ADDRESS="true"
            echo "Found Address in: $f"
        fi
        if grep -Faq "$EXPECTED_ZIP" "$f"; then
            FOUND_ZIP="true"
            echo "Found Zip in: $f"
        fi
        if grep -Faq "$EXPECTED_PHONE" "$f"; then
            FOUND_PHONE="true"
            echo "Found Phone in: $f"
        fi
    done
else
    echo "No relevant config/database files were modified."
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "config_files_modified": $CONFIG_FILE_MODIFIED,
    "data_found": {
        "company": $FOUND_COMPANY,
        "address": $FOUND_ADDRESS,
        "zip": $FOUND_ZIP,
        "phone": $FOUND_PHONE
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="