#!/bin/bash
echo "=== Exporting fix_containerized_cron_job results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/Documents/recurring-report"
REPORTS_DIR="$PROJECT_DIR/reports"

# 1. Check if container is running
CONTAINER_RUNNING=$(docker ps --format '{{.Names}}' | grep -q "sales-cron" && echo "true" || echo "false")

# 2. AUTOMATIC EXECUTION TEST
# To prove the job is running via cron (and not just manually run once by the agent),
# we will clean the reports directory and wait for > 60 seconds.
# If a new report appears, cron is working.

echo "Checking for automatic report generation (waiting 70s)..."

# Clear existing reports (save count first)
EXISTING_COUNT=$(ls -1 "$REPORTS_DIR"/report_*.json 2>/dev/null | wc -l)
rm -f "$REPORTS_DIR"/*.json

# Wait for cron trigger (at least 1 minute boundary)
sleep 70

# Check for NEW files
NEW_FILE_COUNT=$(ls -1 "$REPORTS_DIR"/report_*.json 2>/dev/null | wc -l)
NEW_FILE_PATH=$(ls -1 "$REPORTS_DIR"/report_*.json 2>/dev/null | head -n 1)

AUTOMATIC_GENERATION="false"
REPORT_CONTENT="{}"

if [ "$NEW_FILE_COUNT" -gt 0 ]; then
    AUTOMATIC_GENERATION="true"
    # Read the content of the generated report
    if [ -f "$NEW_FILE_PATH" ]; then
        REPORT_CONTENT=$(cat "$NEW_FILE_PATH")
    fi
fi

# 3. Check for file modifications (Evidence of work)
ENTRYPOINT_MODIFIED="false"
if [ -f "$PROJECT_DIR/entrypoint.sh" ]; then
    MTIME=$(stat -c %Y "$PROJECT_DIR/entrypoint.sh")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        ENTRYPOINT_MODIFIED="true"
    fi
fi

CRONTAB_MODIFIED="false"
if [ -f "$PROJECT_DIR/crontab.txt" ]; then
    MTIME=$(stat -c %Y "$PROJECT_DIR/crontab.txt")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CRONTAB_MODIFIED="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "container_running": $CONTAINER_RUNNING,
    "automatic_generation": $AUTOMATIC_GENERATION,
    "new_files_count": $NEW_FILE_COUNT,
    "report_content": $REPORT_CONTENT,
    "entrypoint_modified": $ENTRYPOINT_MODIFIED,
    "crontab_modified": $CRONTAB_MODIFIED,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="