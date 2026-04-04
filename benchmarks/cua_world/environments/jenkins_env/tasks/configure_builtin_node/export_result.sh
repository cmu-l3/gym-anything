#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting configure_builtin_node results ==="

RESULT_FILE="/tmp/configure_builtin_node_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query built-in node configuration
# Note: In Jenkins API, the built-in node is often accessed via computer/(built-in)
# or via top level api/json for some settings.
BUILTIN_NODE_API=$(jenkins_api "computer/(built-in)/api/json" 2>/dev/null || echo "{}")

# Extract Node Configuration
NUM_EXECUTORS=$(echo "$BUILTIN_NODE_API" | jq -r '.numExecutors // -1')
MODE=$(echo "$BUILTIN_NODE_API" | jq -r '.mode // "unknown"')

# Labels are an array of objects in assignedLabels
ASSIGNED_LABELS=$(echo "$BUILTIN_NODE_API" | jq -r '[.assignedLabels[]?.name] | join(" ")' 2>/dev/null || echo "")

# Also check top-level config for labelString as backup/verification
TOP_LEVEL_API=$(jenkins_api "api/json" 2>/dev/null || echo "{}")
LABEL_STRING_TOP=$(echo "$TOP_LEVEL_API" | jq -r '.labelString // ""' 2>/dev/null || echo "")

# Check Job Configuration
JOB_NAME="controller-health-check"
JOB_EXISTS="false"
JOB_CLASS=""
JOB_LABEL_EXPR=""
JOB_SHELL_COMMAND=""
JOB_HAS_SHELL_STEP="false"
JOB_CAN_ROAM="true"

if job_exists "$JOB_NAME"; then
    JOB_EXISTS="true"
    JOB_API=$(jenkins_api "job/${JOB_NAME}/api/json" 2>/dev/null || echo "{}")
    JOB_CLASS=$(echo "$JOB_API" | jq -r '._class // "unknown"')
    
    # Get config XML to parse detailed settings
    JOB_CONFIG_XML=$(jenkins_api "job/${JOB_NAME}/config.xml" 2>/dev/null || echo "")
    
    if [ -n "$JOB_CONFIG_XML" ]; then
        # Extract label expression (assignedNode)
        JOB_LABEL_EXPR=$(echo "$JOB_CONFIG_XML" | xmlstarlet sel -t -v "//assignedNode" 2>/dev/null || echo "")
        
        # Extract canRoam (should be false if restricted)
        JOB_CAN_ROAM=$(echo "$JOB_CONFIG_XML" | xmlstarlet sel -t -v "//canRoam" 2>/dev/null || echo "true")
        
        # Extract shell command
        # Check for standard shell step
        JOB_SHELL_COMMAND=$(echo "$JOB_CONFIG_XML" | xmlstarlet sel -t -v "//builders/hudson.tasks.Shell/command" 2>/dev/null || echo "")
        
        if [ -n "$JOB_SHELL_COMMAND" ]; then
            JOB_HAS_SHELL_STEP="true"
        fi
    fi
fi

# Load initial state
INITIAL_STATE=$(cat /tmp/initial_state.json 2>/dev/null || echo "{}")

# Build result JSON
# Using jq to construct safe JSON
jq -n \
    --argjson num_executors "$NUM_EXECUTORS" \
    --arg mode "$MODE" \
    --arg assigned_labels "$ASSIGNED_LABELS" \
    --arg label_string_top "$LABEL_STRING_TOP" \
    --argjson job_exists "$JOB_EXISTS" \
    --arg job_class "$JOB_CLASS" \
    --arg job_label_expr "$JOB_LABEL_EXPR" \
    --arg job_can_roam "$JOB_CAN_ROAM" \
    --argjson job_has_shell "$JOB_HAS_SHELL_STEP" \
    --arg job_shell_cmd "$JOB_SHELL_COMMAND" \
    --argjson initial_state "$INITIAL_STATE" \
    --arg task_start "$(cat /tmp/task_start_time.txt 2>/dev/null || echo '0')" \
    '{
        node_config: {
            num_executors: $num_executors,
            mode: $mode,
            assigned_labels: $assigned_labels,
            label_string_top: $label_string_top
        },
        job: {
            exists: $job_exists,
            class: $job_class,
            label_expression: $job_label_expr,
            can_roam: $job_can_roam,
            has_shell_step: $job_has_shell,
            shell_command: $job_shell_cmd
        },
        initial_state: $initial_state,
        task_start_time: $task_start,
        screenshot_path: "/tmp/task_final.png"
    }' > "$RESULT_FILE"

# Make readable by everyone
chmod 666 "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"