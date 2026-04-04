#!/bin/bash
echo "=== Exporting Debugging Task Results ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/FinancialAudit"
SOLUTION_PATH="/home/ga/solution.txt"
INITIAL_HASHES="/tmp/initial_hashes.txt"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check Solution File
SOLUTION_EXISTS="false"
SOLUTION_CONTENT=""
if [ -f "$SOLUTION_PATH" ]; then
    SOLUTION_EXISTS="true"
    SOLUTION_CONTENT=$(cat "$SOLUTION_PATH" | tr -d '\n\r' | sed 's/"/\\"/g')
fi

# 3. Verify Source Code Integrity (Anti-Gaming)
# If files have changed, the agent likely used print statements instead of debugger
INTEGRITY_PASSED="true"
CURRENT_HASHES=$(mktemp)
find "$PROJECT_DIR" -name "*.java" -type f -exec md5sum {} \; | sort > "$CURRENT_HASHES"

# Compare hashes
if ! diff -q "/tmp/initial_hashes.txt" "$CURRENT_HASHES" > /dev/null; then
    INTEGRITY_PASSED="false"
    echo "Integrity Check Failed: Source files were modified."
fi
rm -f "$CURRENT_HASHES"

# 4. Check for Debug Evidence
# Check if Eclipse debug markers or launch configs were created
DEBUG_USED="false"
BREAKPOINT_SET="false"
LAUNCH_CONFIG_EXISTS="false"

WORKSPACE_DIR="/home/ga/eclipse-workspace"

# Check breakpoints file
BREAKPOINTS_FILE="$WORKSPACE_DIR/.metadata/.plugins/org.eclipse.debug.core/.breakpoints"
if [ -f "$BREAKPOINTS_FILE" ]; then
    # File exists and has content
    if [ -s "$BREAKPOINTS_FILE" ]; then
        BREAKPOINT_SET="true"
    fi
fi

# Check launch configs
LAUNCH_DIR="$WORKSPACE_DIR/.metadata/.plugins/org.eclipse.debug.core/.launches"
if [ -d "$LAUNCH_DIR" ]; then
    if ls "$LAUNCH_DIR"/*.launch 1> /dev/null 2>&1; then
        LAUNCH_CONFIG_EXISTS="true"
    fi
fi

# Check window title for "Debug" perspective or debugging state
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if [[ "$WINDOW_TITLE" == *"Debug"* ]] || [[ "$WINDOW_TITLE" == *"FinancialBatchProcessor"* ]]; then
    DEBUG_USED="true"
fi

# 5. Create JSON Result
RESULT_JSON=$(cat << EOF
{
    "solution_exists": $SOLUTION_EXISTS,
    "solution_content": "$SOLUTION_CONTENT",
    "integrity_passed": $INTEGRITY_PASSED,
    "breakpoint_set": $BREAKPOINT_SET,
    "launch_config_exists": $LAUNCH_CONFIG_EXISTS,
    "debug_window_detected": "$DEBUG_USED",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="