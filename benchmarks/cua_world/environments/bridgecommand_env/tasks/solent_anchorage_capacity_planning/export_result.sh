#!/bin/bash
echo "=== Exporting Anchorage Task Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/p) St Helens Storm Anchorage"
RESULT_FILE="/tmp/anchorage_result.json"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence
SCENARIO_EXISTS="false"
ENV_EXISTS="false"
OTHERSHIP_EXISTS="false"
OTHERSHIP_CONTENT=""
ENV_CONTENT=""

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
fi

if [ -f "$SCENARIO_DIR/environment.ini" ]; then
    ENV_EXISTS="true"
    ENV_CONTENT=$(cat "$SCENARIO_DIR/environment.ini" | base64 -w 0)
fi

if [ -f "$SCENARIO_DIR/othership.ini" ]; then
    OTHERSHIP_EXISTS="true"
    OTHERSHIP_CONTENT=$(cat "$SCENARIO_DIR/othership.ini" | base64 -w 0)
fi

# 3. Check File Timestamps (Anti-Gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MOD_TIME=$(stat -c %Y "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$FILE_MOD_TIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# 4. Construct JSON
cat > "$RESULT_FILE" << EOF
{
    "scenario_exists": $SCENARIO_EXISTS,
    "environment_exists": $ENV_EXISTS,
    "othership_exists": $OTHERSHIP_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "othership_content_b64": "$OTHERSHIP_CONTENT",
    "environment_content_b64": "$ENV_CONTENT"
}
EOF

# 5. Move to shared location
cp "$RESULT_FILE" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"