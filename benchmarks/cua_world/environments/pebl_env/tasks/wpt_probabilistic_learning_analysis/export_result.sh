#!/bin/bash
# Export result for wpt_probabilistic_learning_analysis

set -e
echo "=== Exporting task results ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check JSON output
JSON_EXISTS="false"
JSON_MODIFIED="false"
if [ -f "/home/ga/pebl/analysis/wpt_report.json" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "/home/ga/pebl/analysis/wpt_report.json" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Check PNG output
PNG_EXISTS="false"
PNG_MODIFIED="false"
PNG_SIZE="0"
if [ -f "/home/ga/pebl/analysis/wpt_learning_curve.png" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "/home/ga/pebl/analysis/wpt_learning_curve.png" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "/home/ga/pebl/analysis/wpt_learning_curve.png" 2>/dev/null || echo "0")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_MODIFIED="true"
    fi
fi

# Take final screenshot for VLM verification of the environment
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Export a summary payload for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "json_exists": $JSON_EXISTS,
    "json_created_during_task": $JSON_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "png_size_bytes": $PNG_SIZE,
    "png_created_during_task": $PNG_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="