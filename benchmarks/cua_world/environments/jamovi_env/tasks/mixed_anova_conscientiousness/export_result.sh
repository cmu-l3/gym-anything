#!/bin/bash
echo "=== Exporting Mixed ANOVA Result ==="

# 1. Define Paths
TASK_START_FILE="/tmp/task_start_time.txt"
OMV_PATH="/home/ga/Documents/Jamovi/MixedANOVA_Conscientiousness.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/mixed_anova_report.txt"
GT_PATH="/var/lib/jamovi_ground_truth/mixed_anova_results.json"

TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Check OMV File
OMV_EXISTS=false
OMV_CREATED_DURING=false
OMV_SIZE=0

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS=true
    OMV_MTIME=$(stat -c %Y "$OMV_PATH")
    OMV_SIZE=$(stat -c %s "$OMV_PATH")
    
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING=true
    fi
fi

# 3. Check Report File
REPORT_EXISTS=false
REPORT_CREATED_DURING=false

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING=true
    fi
fi

# 4. Check Application State
APP_RUNNING=$(pgrep -f "org.jamovi.jamovi" > /dev/null && echo "true" || echo "false")

# 5. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Copy Ground Truth for Verifier (Verification runs on host, needs access via copy_from_env)
# We place it in /tmp so it's easily accessible alongside result.json
cp "$GT_PATH" /tmp/mixed_anova_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/mixed_anova_ground_truth.json 2>/dev/null || true

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING,
    "omv_size_bytes": $OMV_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "app_was_running": $APP_RUNNING,
    "ground_truth_path": "/tmp/mixed_anova_ground_truth.json",
    "report_path": "$REPORT_PATH"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"