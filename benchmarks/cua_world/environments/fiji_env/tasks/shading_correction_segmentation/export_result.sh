#!/bin/bash
echo "=== Exporting Shading Correction Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task started at: $TASK_START"

# 3. Define output paths
MASK_PATH="/home/ga/Fiji_Data/results/corrected_mask.png"
CSV_PATH="/home/ga/Fiji_Data/results/particle_count.csv"
RESULT_JSON="/tmp/shading_result.json"

# 4. Check File Existence & Timestamps
MASK_EXISTS="false"
MASK_CREATED_DURING_TASK="false"
if [ -f "$MASK_PATH" ]; then
    MASK_EXISTS="true"
    MTIME=$(stat -c %Y "$MASK_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        MASK_CREATED_DURING_TASK="true"
    fi
fi

CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
PARTICLE_COUNT=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Try to parse particle count (number of lines minus header)
    # Using python for robustness against empty lines/bad formatting
    PARTICLE_COUNT=$(python3 -c "
import sys
try:
    with open('$CSV_PATH', 'r') as f:
        lines = [l.strip() for l in f.readlines() if l.strip()]
        # Assume first line is header if content exists
        count = len(lines) - 1 if len(lines) > 0 else 0
        print(max(0, count))
except:
    print(0)
")
fi

# 5. Check if Fiji is still running
APP_RUNNING=$(pgrep -f "fiji\|imagej" > /dev/null && echo "true" || echo "false")

# 6. Create JSON payload
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "mask_exists": $MASK_EXISTS,
    "mask_created_during_task": $MASK_CREATED_DURING_TASK,
    "mask_path": "$MASK_PATH",
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "particle_count": $PARTICLE_COUNT,
    "app_running": $APP_RUNNING,
    "final_screenshot": "/tmp/task_final.png"
}
EOF

# 7. Set permissions so the verifier (running as root/different user) can read it
chmod 666 "$RESULT_JSON" 2>/dev/null || true
if [ -f "$MASK_PATH" ]; then chmod 644 "$MASK_PATH"; fi

echo "Export complete. Result:"
cat "$RESULT_JSON"