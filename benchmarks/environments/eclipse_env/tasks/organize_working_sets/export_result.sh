#!/bin/bash
echo "=== Exporting organize_working_sets result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

WORKSPACE_DIR="/home/ga/eclipse-workspace"
WORKINGSETS_XML="$WORKSPACE_DIR/.metadata/.plugins/org.eclipse.ui.workbench/workingsets.xml"

# Check if working sets file exists
XML_EXISTS="false"
XML_CONTENT=""

if [ -f "$WORKINGSETS_XML" ]; then
    XML_EXISTS="true"
    # Read content
    XML_CONTENT=$(cat "$WORKINGSETS_XML")
fi

# Determine if file was modified/created during task
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ -f "$WORKINGSETS_XML" ]; then
    FILE_MTIME=$(stat -c %Y "$WORKINGSETS_XML" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Capture the Package Explorer state is hard programmatically (it's in complex workbench.xml or binary prefs)
# We will rely on VLM for the visual check of the View state.
# But the DATA check (XML content) is robust.

# Escape XML for JSON
XML_ESCAPED=$(echo "$XML_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create result JSON
RESULT_JSON=$(cat << EOF
{
    "xml_exists": $XML_EXISTS,
    "xml_modified_during_task": $FILE_MODIFIED,
    "xml_content": $XML_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="