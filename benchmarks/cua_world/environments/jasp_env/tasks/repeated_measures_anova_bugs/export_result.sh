#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

JASP_FILE="/home/ga/Documents/JASP/BugsRM.jasp"
REPORT_FILE="/home/ga/Documents/JASP/bugs_rm_report.txt"
GROUND_TRUTH_FILE="/var/lib/jasp/bugs_ground_truth.json"

# Check JASP file
JASP_EXISTS="false"
JASP_CREATED_DURING="false"
if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# Check Report file
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare files for extraction
# We copy report and ground truth to a temp location that is accessible and cleanly named
cp "$REPORT_FILE" /tmp/exported_report.txt 2>/dev/null || true
cp "$GROUND_TRUTH_FILE" /tmp/exported_ground_truth.json 2>/dev/null || true
# We don't necessarily need to copy the full JASP file (it's a zip), but checking its header might be useful if needed.
# For now, we rely on existence.

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_created_during_task": $JASP_CREATED_DURING,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_created_during_task": $REPORT_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="