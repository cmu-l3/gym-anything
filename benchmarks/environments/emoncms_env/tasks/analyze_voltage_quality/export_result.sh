#!/bin/bash
echo "=== Exporting Analyze Voltage Quality Results ==="

# Source helper functions
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
REPORT_PATH="/home/ga/voltage_quality_report.json"
TRUTH_PATH="/var/lib/emoncms/ground_truth/voltage_truth.json"

# Check if output file was created/modified during task
if [ -f "$REPORT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare files for extraction
# We copy them to /tmp/export_stage with generic names for clean extraction
mkdir -p /tmp/export_stage
rm -f /tmp/export_stage/*

# Copy report if exists
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$REPORT_PATH" /tmp/export_stage/agent_report.json
fi

# Copy ground truth (always exists if setup ran correctly)
if [ -f "$TRUTH_PATH" ]; then
    cp "$TRUTH_PATH" /tmp/export_stage/ground_truth.json
fi

# Create result manifest
cat > /tmp/export_stage/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Make everything readable
chmod -R 644 /tmp/export_stage/*

# Move the stage directory content to where copy_from_env can easily grab it
# We'll rely on the verifier to copy individual files from /tmp/export_stage/
echo "Files prepared in /tmp/export_stage/"
ls -la /tmp/export_stage/

echo "=== Export complete ==="