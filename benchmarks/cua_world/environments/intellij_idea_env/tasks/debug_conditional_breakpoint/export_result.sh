#!/bin/bash
echo "=== Exporting Debug Task Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/DataBatchAnalyzer"
SOURCE_FILE="$PROJECT_DIR/src/main/java/com/example/Main.java"
SOLUTION_FILE="/home/ga/solution.txt"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check Solution File
SOLUTION_EXISTS="false"
SOLUTION_CONTENT=""
if [ -f "$SOLUTION_FILE" ]; then
    SOLUTION_EXISTS="true"
    SOLUTION_CONTENT=$(cat "$SOLUTION_FILE" | tr -d ' \n\r')
fi

# 2. Check Source Code Integrity (Did they modify the code to print the value?)
SOURCE_MODIFIED="false"
CURRENT_HASH=$(md5sum "$SOURCE_FILE" 2>/dev/null | awk '{print $1}')
ORIGINAL_HASH=$(cat /var/lib/task/original_source_hash.txt 2>/dev/null)

if [ "$CURRENT_HASH" != "$ORIGINAL_HASH" ]; then
    SOURCE_MODIFIED="true"
fi

# 3. Check for Debugger Usage via VLM Artifacts
# (We assume the screenshot captured might show the debugger active)
# We also check if the .idea/workspace.xml contains breakpoint info, though reliable parsing is hard.
# A simple grep might hint if a breakpoint was ever added.
BREAKPOINT_HINT="false"
if grep -r "breakpoint" "$PROJECT_DIR/.idea" 2>/dev/null | grep -q "line-breakpoint"; then
    BREAKPOINT_HINT="true"
fi

# Prepare Result JSON
RESULT_JSON=$(cat << EOF
{
    "solution_exists": $SOLUTION_EXISTS,
    "solution_content": "$SOLUTION_CONTENT",
    "source_modified": $SOURCE_MODIFIED,
    "breakpoint_hint": $BREAKPOINT_HINT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="