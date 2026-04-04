#!/bin/bash
echo "=== Exporting compute_hydraulic_geometry results ==="

source /workspace/scripts/task_utils.sh

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_PATH="$RESULTS_DIR/hydraulic_properties.csv"
SUMMARY_PATH="$RESULTS_DIR/cross_section_summary.txt"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for output files
CSV_EXISTS="false"
SUMMARY_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Check modification time
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
fi

# 3. Find any python scripts the agent created (evidence of work)
# We look for .py files created after task start in likely locations
AGENT_SCRIPTS=""
find /home/ga -name "*.py" -newermt "@$TASK_START" 2>/dev/null | head -5 | while read -r script; do
    AGENT_SCRIPTS="$AGENT_SCRIPTS $script"
done

# 4. Copy files to temp for verification (handle permissions)
cp "$CSV_PATH" /tmp/hydraulic_properties.csv 2>/dev/null || true
cp "$SUMMARY_PATH" /tmp/cross_section_summary.txt 2>/dev/null || true
chmod 644 /tmp/hydraulic_properties.csv /tmp/cross_section_summary.txt 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "summary_exists": $SUMMARY_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_path": "$CSV_PATH",
    "summary_path": "$SUMMARY_PATH",
    "screenshot_path": "/tmp/task_final.png",
    "agent_scripts": "$AGENT_SCRIPTS"
}
EOF

# Safe move to /tmp/task_result.json
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json