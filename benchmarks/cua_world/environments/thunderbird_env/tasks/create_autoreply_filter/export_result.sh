#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

TB_PROFILE="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${TB_PROFILE}/Mail/Local Folders"
TEMPLATES_FILE="${LOCAL_MAIL_DIR}/Templates"
RULES_FILE="${LOCAL_MAIL_DIR}/msgFilterRules.dat"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Copy relevant files to /tmp for easy retrieval by verifier
rm -f /tmp/export_Templates /tmp/export_msgFilterRules.dat
if [ -f "$TEMPLATES_FILE" ]; then
    cp "$TEMPLATES_FILE" /tmp/export_Templates
    TEMPLATES_MTIME=$(stat -c %Y "$TEMPLATES_FILE" 2>/dev/null || echo "0")
else
    TEMPLATES_MTIME="0"
fi

if [ -f "$RULES_FILE" ]; then
    cp "$RULES_FILE" /tmp/export_msgFilterRules.dat
    RULES_MTIME=$(stat -c %Y "$RULES_FILE" 2>/dev/null || echo "0")
else
    RULES_MTIME="0"
fi

# Ensure correct permissions for reading
chmod 666 /tmp/export_Templates 2>/dev/null || true
chmod 666 /tmp/export_msgFilterRules.dat 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "templates_mtime": $TEMPLATES_MTIME,
    "rules_mtime": $RULES_MTIME,
    "tb_running": $(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")
}
EOF

# Move JSON to accessible location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="