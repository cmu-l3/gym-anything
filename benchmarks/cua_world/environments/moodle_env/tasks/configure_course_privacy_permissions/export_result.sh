#!/bin/bash
# Export script for Privacy Permissions task

echo "=== Exporting Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve IDs stored during setup
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null)
CONTEXT_ID=$(cat /tmp/target_context_id 2>/dev/null)
ROLE_ID=$(cat /tmp/target_role_id 2>/dev/null)
INITIAL_GLOBAL_PERM=$(cat /tmp/initial_global_perm 2>/dev/null || echo "0")

echo "Checking permissions for Course $COURSE_ID (Context $CONTEXT_ID), Role $ROLE_ID..."

# 1. Check Course-Level Override
# We look for a record in mdl_role_capabilities
# permission values: 1 = Allow, -1 = Prevent, -1000 = Prohibit
COURSE_OVERRIDE_DATA=$(moodle_query "SELECT permission, timemodified FROM mdl_role_capabilities WHERE contextid=$CONTEXT_ID AND roleid=$ROLE_ID AND capability='moodle/course:viewparticipants'")

COURSE_HAS_OVERRIDE="false"
COURSE_PERMISSION_VALUE="0"
COURSE_MODIFIED_TIME="0"

if [ -n "$COURSE_OVERRIDE_DATA" ]; then
    COURSE_HAS_OVERRIDE="true"
    COURSE_PERMISSION_VALUE=$(echo "$COURSE_OVERRIDE_DATA" | cut -f1 | tr -d '[:space:]')
    COURSE_MODIFIED_TIME=$(echo "$COURSE_OVERRIDE_DATA" | cut -f2 | tr -d '[:space:]')
    echo "Found course override: Value=$COURSE_PERMISSION_VALUE, Modified=$COURSE_MODIFIED_TIME"
else
    echo "No course override found."
fi

# 2. Check System-Level (Global) Override
# To detect if the agent incorrectly changed the global role definition
SYSTEM_CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=10 ORDER BY id ASC LIMIT 1" | tr -d '[:space:]')
GLOBAL_OVERRIDE_DATA=$(moodle_query "SELECT permission FROM mdl_role_capabilities WHERE contextid=$SYSTEM_CONTEXT_ID AND roleid=$ROLE_ID AND capability='moodle/course:viewparticipants'")

GLOBAL_PERMISSION_VALUE=${GLOBAL_OVERRIDE_DATA:-0}
GLOBAL_CHANGED="false"

# Normalize empty result to 0
if [ -z "$GLOBAL_PERMISSION_VALUE" ]; then GLOBAL_PERMISSION_VALUE="0"; fi

if [ "$GLOBAL_PERMISSION_VALUE" != "$INITIAL_GLOBAL_PERM" ]; then
    GLOBAL_CHANGED="true"
    echo "WARNING: Global permission changed from $INITIAL_GLOBAL_PERM to $GLOBAL_PERMISSION_VALUE"
else
    echo "Global permission unchanged ($GLOBAL_PERMISSION_VALUE)"
fi

# 3. Check Task Timing (Anti-Gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MODIFIED_DURING_TASK="false"

if [ "$COURSE_HAS_OVERRIDE" = "true" ]; then
    if [ "$COURSE_MODIFIED_TIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
fi

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/privacy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_context_id": ${CONTEXT_ID:-0},
    "course_override_found": $COURSE_HAS_OVERRIDE,
    "course_permission_value": ${COURSE_PERMISSION_VALUE:-0},
    "override_modified_timestamp": ${COURSE_MODIFIED_TIME:-0},
    "modified_during_task": $MODIFIED_DURING_TASK,
    "global_permission_value": ${GLOBAL_PERMISSION_VALUE:-0},
    "global_permission_changed": $GLOBAL_CHANGED,
    "task_start_time": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="