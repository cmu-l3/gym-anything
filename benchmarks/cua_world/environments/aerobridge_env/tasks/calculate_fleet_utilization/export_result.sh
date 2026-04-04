#!/bin/bash
# export_result.sh — post_task hook for calculate_fleet_utilization

echo "=== Exporting calculate_fleet_utilization result ==="

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/utilization_report.txt"

# Check if report exists
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 100) # Read first 100 chars
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task (compare mtime with task start)
    # Convert TASK_START to epoch if it's ISO, or handle if it's already epoch
    # In setup_task.sh we used `date -u +"%Y-%m-%dT%H:%M:%SZ"`. Let's use `date +%s` there next time, 
    # but here we can just use file existence check vs a known start timestamp if available.
    # Actually, simpler: just check if file is newer than /tmp/task_start_time file itself
    if [ "$REPORT_PATH" -nt "/tmp/task_start_time" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_content": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g')",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start": "$TASK_START",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="