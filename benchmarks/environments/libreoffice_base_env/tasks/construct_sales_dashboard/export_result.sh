#!/bin/bash
echo "=== Exporting construct_sales_dashboard result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database File Status
ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    
    # Check modification time
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
    
    # Backup check using checksum
    CURRENT_SUM=$(md5sum "$ODB_PATH" | awk '{print $1}')
    INITIAL_SUM=$(cat /tmp/initial_odb_checksum.txt 2>/dev/null | awk '{print $1}' || echo "")
    
    if [ "$CURRENT_SUM" != "$INITIAL_SUM" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 3. Check if LibreOffice is running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 4. Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move files for verification
# Copy ODB to temp location for the verifier to unzip/inspect
cp "$ODB_PATH" /tmp/verification_chinook.odb 2>/dev/null || true
chmod 644 /tmp/verification_chinook.odb 2>/dev/null || true

# Save JSON result
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Cleanup
# We kill LibreOffice here to ensure clean state for next task, 
# but only after we've exported what we need.
kill_libreoffice

echo "=== Export complete ==="