#!/bin/bash
set -e
echo "=== Exporting manage_user_permissions result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
ODB_PATH="/home/ga/chinook.odb"
EXTRACT_DIR="/tmp/odb_extract"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")

# Check if ODB exists and was modified
ODB_EXISTS="false"
ODB_MODIFIED="false"
SCRIPT_EXTRACTED="false"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$ODB_PATH")
    
    # Check if modified since start (and different from initial)
    if [ "$CURRENT_MTIME" -gt "$TASK_START" ] && [ "$CURRENT_MTIME" != "$INITIAL_MTIME" ]; then
        ODB_MODIFIED="true"
    fi

    # Extract the HSQLDB script file from the ODB (which is a zip)
    # The script file contains the SQL commands executed/saved
    echo "Extracting database/script from ODB..."
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    
    # Unzip specific file: database/script
    if unzip -p "$ODB_PATH" "database/script" > "$EXTRACT_DIR/script" 2>/dev/null; then
        SCRIPT_EXTRACTED="true"
        echo "Successfully extracted database script."
    else
        echo "Failed to extract database script."
    fi
fi

# Check if LibreOffice is running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "script_extracted": $SCRIPT_EXTRACTED,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result JSON
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# If script was extracted, make it available for the verifier
if [ "$SCRIPT_EXTRACTED" = "true" ]; then
    cp "$EXTRACT_DIR/script" /tmp/database_script.txt
    chmod 666 /tmp/database_script.txt
fi

echo "Result exported to /tmp/task_result.json"