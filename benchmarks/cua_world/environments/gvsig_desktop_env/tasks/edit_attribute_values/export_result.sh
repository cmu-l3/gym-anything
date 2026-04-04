#!/bin/bash
echo "=== Exporting edit_attribute_values result ==="

source /workspace/scripts/task_utils.sh

# Paths
DBF_PATH="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.dbf"
LOCK_FILE="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp.lock" # Standard lock pattern?
# gvSIG often uses .mck or similar for locks, or just Java file locks.
# We'll check common patterns.

# 1. Record Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DBF_MTIME=$(stat -c %Y "$DBF_PATH" 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_dbf_mtime.txt 2>/dev/null || echo "0")

# 2. Check for File Modification
FILE_MODIFIED="false"
if [ "$DBF_MTIME" -gt "$INITIAL_MTIME" ]; then
    FILE_MODIFIED="true"
fi

# 3. Check for Active Editing (Lock files)
# gvSIG 2.x often creates a .lock file next to the shp/dbf or uses system locks
IS_LOCKED="false"
if [ -f "$DBF_PATH.lock" ] || [ -f "${DBF_PATH%.dbf}.shp.lock" ]; then
    IS_LOCKED="true"
fi
# Also check lsof if available to see if java process holds the file
if lsof "$DBF_PATH" > /dev/null 2>&1; then
    IS_LOCKED="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Prepare data for verifier
# We need to send the DBF file content to the verifier.
# Since it's binary, we'll copy it to a temp location that verifier can access via copy_from_env
cp "$DBF_PATH" /tmp/result_countries.dbf
chmod 644 /tmp/result_countries.dbf

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dbf_modified": $FILE_MODIFIED,
    "dbf_mtime": $DBF_MTIME,
    "is_locked": $IS_LOCKED,
    "dbf_path": "/tmp/result_countries.dbf",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "DBF copied to /tmp/result_countries.dbf"
echo "=== Export complete ==="