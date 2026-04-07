#!/bin/bash
echo "=== Exporting Science Plan Translation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/science_plan_translation_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)
JSON_OUTPUT="/home/ga/Desktop/pass_summary.json"
SCRIPT_OUTPUT="/home/ga/Desktop/run_observations.py"

# Check output files
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_MTIME=0

SCRIPT_EXISTS=false
SCRIPT_IS_NEW=false
SCRIPT_MTIME=0

if [ -f "$JSON_OUTPUT" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON_OUTPUT" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW=true
    fi
fi

if [ -f "$SCRIPT_OUTPUT" ]; then
    SCRIPT_EXISTS=true
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_OUTPUT" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_IS_NEW=true
    fi
fi

# Record final COLLECTS telemetry value
INITIAL_COLLECTS=$(cat /tmp/science_plan_translation_initial_collects 2>/dev/null || echo "0")
FINAL_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")

echo "Initial COLLECTS: $INITIAL_COLLECTS"
echo "Final COLLECTS: $FINAL_COLLECTS"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/science_plan_translation_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/science_plan_translation_end.png 2>/dev/null || true

cat > /tmp/science_plan_translation_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_mtime": $JSON_MTIME,
    "script_exists": $SCRIPT_EXISTS,
    "script_is_new": $SCRIPT_IS_NEW,
    "script_mtime": $SCRIPT_MTIME,
    "initial_collects": $INITIAL_COLLECTS,
    "final_collects": $FINAL_COLLECTS
}
EOF

echo "JSON Report exists: $JSON_EXISTS (New: $JSON_IS_NEW)"
echo "Automation Script exists: $SCRIPT_EXISTS (New: $SCRIPT_IS_NEW)"
echo "=== Export Complete ==="