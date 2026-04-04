#!/bin/bash
echo "=== Exporting run_and_debug result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/gs-maven"
WORKSPACE_DIR="/home/ga/eclipse-workspace"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check for evidence of program execution
PROGRAM_RAN="false"
DEBUG_USED="false"
BREAKPOINT_SET="false"
LAUNCH_FILE_EXISTS="false"
BREAKPOINT_FILE_EXISTS="false"

# Check Eclipse workspace metadata for launch configurations
LAUNCH_DIR="$WORKSPACE_DIR/.metadata/.plugins/org.eclipse.debug.core/.launches"
if [ -d "$LAUNCH_DIR" ]; then
    # Look for any .launch file
    LAUNCH_FILES=$(ls "$LAUNCH_DIR"/*.launch 2>/dev/null || true)
    if [ -n "$LAUNCH_FILES" ]; then
        LAUNCH_FILE_EXISTS="true"
        # Check if any launch config mentions HelloWorld or gs-maven
        if grep -l -r "HelloWorld\|hello\|gs-maven" "$LAUNCH_DIR"/*.launch 2>/dev/null; then
            PROGRAM_RAN="true"
        fi
    fi
fi

# Check for breakpoint file (primary evidence)
BREAKPOINT_FILE="$WORKSPACE_DIR/.metadata/.plugins/org.eclipse.debug.core/.breakpoints"
if [ -f "$BREAKPOINT_FILE" ]; then
    BREAKPOINT_FILE_EXISTS="true"
    # Check if breakpoint is on HelloWorld
    if grep -q "HelloWorld\|hello" "$BREAKPOINT_FILE" 2>/dev/null; then
        BREAKPOINT_SET="true"
    elif [ -s "$BREAKPOINT_FILE" ]; then
        # File exists and has content = some breakpoint was set
        BREAKPOINT_SET="true"
    fi
fi

# Check for debug perspective/UI evidence
DEBUG_UI_DIR="$WORKSPACE_DIR/.metadata/.plugins/org.eclipse.debug.ui"
if [ -d "$DEBUG_UI_DIR" ]; then
    if [ -f "$DEBUG_UI_DIR/launchConfigurationHistory.xml" ]; then
        DEBUG_USED="true"
    fi
fi

# Check workbench state for Debug perspective
WORKBENCH_FILE="$WORKSPACE_DIR/.metadata/.plugins/org.eclipse.e4.workbench/workbench.xmi"
if [ -f "$WORKBENCH_FILE" ]; then
    if grep -qi "debug" "$WORKBENCH_FILE" 2>/dev/null; then
        DEBUG_USED="true"
    fi
fi

# Check window titles for Debug perspective
WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || true)
if echo "$WINDOWS" | grep -qi "debug"; then
    DEBUG_USED="true"
fi

# Check if project is compiled
PROJECT_COMPILED="false"
if [ -f "$PROJECT_DIR/target/classes/hello/HelloWorld.class" ]; then
    PROJECT_COMPILED="true"
fi

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "program_ran": $PROGRAM_RAN,
    "debug_used": $DEBUG_USED,
    "breakpoint_set": $BREAKPOINT_SET,
    "launch_file_exists": $LAUNCH_FILE_EXISTS,
    "breakpoint_file_exists": $BREAKPOINT_FILE_EXISTS,
    "project_compiled": $PROJECT_COMPILED,
    "windows_detected": "$(echo "$WINDOWS" | tr '\n' ' ')",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
