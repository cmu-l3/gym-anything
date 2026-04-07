#!/bin/bash
set -e

echo "=== Exporting Custom SAST Scanner Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
WORKSPACE_DIR="/home/ga/workspace/sast_scanner"
VISITOR_FILE="$WORKSPACE_DIR/visitor.py"

# Best-effort: save all open files in VSCode
DISPLAY=:1 xdotool key --delay 100 ctrl+shift+s 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key --delay 100 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

FILE_MODIFIED_DURING_TASK="false"
if [ -f "$VISITOR_FILE" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$VISITOR_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 1. Run public tests and capture output
echo "Running pytest..."
su - ga -c "cd $WORKSPACE_DIR && pytest tests/test_visitor.py -v" > /tmp/pytest_output.txt 2>&1 || true

# 2. Run scanner against hidden eval codebase
echo "Running hidden evaluation..."
su - ga -c "cd $WORKSPACE_DIR && python3 scanner.py /var/lib/app/hidden_eval_codebase/ -o /tmp/hidden_eval.json" > /tmp/hidden_eval_logs.txt 2>&1 || true

# Read the files into variables for JSON export
PYTEST_OUT=$(cat /tmp/pytest_output.txt | tr -d '\000-\011\013\014\016-\037' | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')
if [ -f "/tmp/hidden_eval.json" ]; then
    HIDDEN_EVAL=$(cat /tmp/hidden_eval.json)
else
    HIDDEN_EVAL="{}"
fi

# Read modified visitor.py content
if [ -f "$VISITOR_FILE" ]; then
    VISITOR_CONTENT=$(cat "$VISITOR_FILE" | tr -d '\000-\011\013\014\016-\037' | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')
else
    VISITOR_CONTENT=""
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "pytest_output": "$PYTEST_OUT",
    "hidden_eval": $HIDDEN_EVAL,
    "visitor_content": "$VISITOR_CONTENT"
}
EOF

# Move to final location
sudo cp "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="