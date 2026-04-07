#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting GraphQL API Result ==="

WORKSPACE_DIR="/home/ga/workspace/graphql_api"
RESULT_FILE="/tmp/task_result.json"

TASK_START=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Check if resolvers.js was modified
FILE_MODIFIED="false"
if [ -f "$WORKSPACE_DIR/src/resolvers.js" ]; then
    CURRENT_MTIME=$(stat -c %Y "$WORKSPACE_DIR/src/resolvers.js" 2>/dev/null || echo "0")
    START_MTIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    if [ "$CURRENT_MTIME" -gt "$START_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Run hidden verification script
echo "Running hidden verification suite..."
sudo -u ga bash -c "cd $WORKSPACE_DIR && node /tmp/hidden_verify.js" > /tmp/hidden_verify.log 2>&1 || true

# Extract hidden test results
TEST_RESULTS="{}"
if [ -f "/tmp/graphql_api_test_results.json" ]; then
    TEST_RESULTS=$(cat /tmp/graphql_api_test_results.json)
fi

# Generate final unified result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "test_results": $TEST_RESULTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safely place the result file
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_FILE"
echo "=== Export complete ==="