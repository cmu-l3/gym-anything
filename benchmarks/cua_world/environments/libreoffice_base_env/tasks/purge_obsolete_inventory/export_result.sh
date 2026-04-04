#!/bin/bash
echo "=== Exporting purge_obsolete_inventory results ==="

source /workspace/scripts/task_utils.sh

# 1. Close LibreOffice to ensure buffers are flushed to ODB file
kill_libreoffice

# 2. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check for ODB modification
ODB_PATH="/home/ga/chinook.odb"
ODB_MODIFIED="false"
if [ -f "$ODB_PATH" ]; then
    MTIME=$(stat -c %Y "$ODB_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 4. Prepare Result Data
# We copy the ODB and the ground truth to a temp location for the verifier
cp "$ODB_PATH" /tmp/result_chinook.odb
cp /tmp/ground_truth_unsold.json /tmp/result_ground_truth.json
cp /tmp/ground_truth_counts.json /tmp/result_counts.json

# Take a screenshot of the desktop (though app is closed now, it proves clean exit)
# Note: Ideally we captured one before closing, but the primary verification here is the file.
take_screenshot /tmp/task_final.png

# 5. Create JSON Wrapper
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_modified": $ODB_MODIFIED,
    "odb_path": "/tmp/result_chinook.odb",
    "ground_truth_path": "/tmp/result_ground_truth.json",
    "counts_path": "/tmp/result_counts.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"