#!/bin/bash
echo "=== Exporting Wind Farm Scenario Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SCENARIO_DIR="/opt/bridgecommand/Scenarios/w) Solent Wind Farm Assessment"
DOC_PATH="/home/ga/Documents/notice_to_mariners_014.txt"
RESULT_JSON="/tmp/task_result.json"

# 1. Check if files exist and were created during task
SCENARIO_CREATED="false"
ENV_INI_EXISTS="false"
OWNSHIP_INI_EXISTS="false"
OTHERSHIP_INI_EXISTS="false"
DOC_EXISTS="false"
DOC_CREATED_DURING_TASK="false"

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_CREATED="true"
    [ -f "$SCENARIO_DIR/environment.ini" ] && ENV_INI_EXISTS="true"
    [ -f "$SCENARIO_DIR/ownship.ini" ] && OWNSHIP_INI_EXISTS="true"
    [ -f "$SCENARIO_DIR/othership.ini" ] && OTHERSHIP_INI_EXISTS="true"
fi

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$DOC_MTIME" -gt "$TASK_START" ]; then
        DOC_CREATED_DURING_TASK="true"
    fi
fi

# 2. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Copy critical files to /tmp for the verifier to access via copy_from_env
# We copy them to filenames with known paths
if [ "$OTHERSHIP_INI_EXISTS" = "true" ]; then
    cp "$SCENARIO_DIR/othership.ini" /tmp/verify_othership.ini
    chmod 666 /tmp/verify_othership.ini
fi

if [ "$DOC_EXISTS" = "true" ]; then
    cp "$DOC_PATH" /tmp/verify_document.txt
    chmod 666 /tmp/verify_document.txt
fi

# 4. Create metadata JSON
cat > "$RESULT_JSON" << EOF
{
    "scenario_created": $SCENARIO_CREATED,
    "env_ini_exists": $ENV_INI_EXISTS,
    "ownship_ini_exists": $OWNSHIP_INI_EXISTS,
    "othership_ini_exists": $OTHERSHIP_INI_EXISTS,
    "othership_path": "/tmp/verify_othership.ini",
    "doc_exists": $DOC_EXISTS,
    "doc_created_during_task": $DOC_CREATED_DURING_TASK,
    "doc_path": "/tmp/verify_document.txt",
    "timestamp": $(date +%s)
}
EOF

chmod 666 "$RESULT_JSON"
echo "Export complete. Result saved to $RESULT_JSON"