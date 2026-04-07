#!/bin/bash
echo "=== Exporting edit_department task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load initial state info
INITIAL_DEPT_ID=$(cat /tmp/initial_dept_id.txt 2>/dev/null || echo "")
INITIAL_DEPT_NAME=$(cat /tmp/initial_dept_name.txt 2>/dev/null || echo "")
INITIAL_ASSOC_COUNT=$(cat /tmp/initial_assoc_count.txt 2>/dev/null || echo "0")

echo "Initial ID: $INITIAL_DEPT_ID"

# 1. Check state of the SPECIFIC department ID we started with
CURRENT_NAME=""
CURRENT_SHORT=""
CURRENT_ASSOC_COUNT="0"
ID_PRESERVED="false"

if [ -n "$INITIAL_DEPT_ID" ]; then
    CURRENT_NAME=$(opencad_db_query "SELECT department_name FROM departments WHERE department_id = $INITIAL_DEPT_ID")
    CURRENT_SHORT=$(opencad_db_query "SELECT department_short_name FROM departments WHERE department_id = $INITIAL_DEPT_ID")
    CURRENT_ASSOC_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM user_departments WHERE department_id = $INITIAL_DEPT_ID")
    
    if [ -n "$CURRENT_NAME" ]; then
        ID_PRESERVED="true"
    fi
fi

# 2. Check if the target name/shortname exists ANYWHERE (in case they deleted and recreated)
NEW_NAME_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM departments WHERE TRIM(department_name) = 'Haul Road Patrol'")
NEW_SHORT_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM departments WHERE TRIM(department_short_name) = 'HRP'")

# 3. Check if the OLD name still exists anywhere
OLD_NAME_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM departments WHERE department_name LIKE '%Highway Patrol%'")

# 4. JSON Escaping for strings
SAFE_CURRENT_NAME=$(json_escape "$CURRENT_NAME")
SAFE_CURRENT_SHORT=$(json_escape "$CURRENT_SHORT")
SAFE_INITIAL_NAME=$(json_escape "$INITIAL_DEPT_NAME")

# Create JSON result
# We use a temporary file and then move it to handle potential permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_id": "${INITIAL_DEPT_ID}",
    "initial_name": "${SAFE_INITIAL_NAME}",
    "initial_assoc_count": ${INITIAL_ASSOC_COUNT},
    "current_state_at_id": {
        "exists": ${ID_PRESERVED},
        "name": "${SAFE_CURRENT_NAME}",
        "short_name": "${SAFE_CURRENT_SHORT}",
        "assoc_count": ${CURRENT_ASSOC_COUNT:-0}
    },
    "global_checks": {
        "new_name_count": ${NEW_NAME_EXISTS:-0},
        "new_short_count": ${NEW_SHORT_EXISTS:-0},
        "old_name_count": ${OLD_NAME_EXISTS:-0}
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="