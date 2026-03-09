#!/bin/bash
echo "=== Exporting neural_network_abalone results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JASP_FILE="/home/ga/Documents/JASP/Abalone_NeuralNet.jasp"
TXT_FILE="/home/ga/Documents/JASP/abalone_performance.txt"

# Check JASP file
JASP_EXISTS="false"
JASP_SIZE="0"
if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE")
fi

# Check Text file
TXT_EXISTS="false"
TXT_CONTENT=""
if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
    TXT_CONTENT=$(head -n 1 "$TXT_FILE")
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_path": "$JASP_FILE",
    "jasp_file_size": $JASP_SIZE,
    "txt_file_exists": $TXT_EXISTS,
    "txt_content": "$TXT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="