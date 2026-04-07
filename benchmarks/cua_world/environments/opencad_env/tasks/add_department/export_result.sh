#!/bin/bash
echo "=== Exporting add_department result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state evidence
take_screenshot /tmp/task_final.png

# 2. Get verification data
INITIAL_COUNT=$(cat /tmp/initial_dept_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM departments")

# 3. Search for the specific department
# We check for exact name match as requested
DEPT_FOUND="false"
DEPT_ID=""
DEPT_NAME=""
DEPT_SHORT=""

# Query by expected name
SEARCH_NAME="Mine Safety Division"
DEPT_ID=$(opencad_db_query "SELECT department_id FROM departments WHERE LOWER(department_name) = LOWER('$SEARCH_NAME') LIMIT 1")

if [ -n "$DEPT_ID" ]; then
    DEPT_FOUND="true"
    DEPT_NAME=$(opencad_db_query "SELECT department_name FROM departments WHERE department_id=${DEPT_ID}")
    
    # Try standard column names for short name (OpenCAD schemas vary)
    DEPT_SHORT=$(opencad_db_query "SELECT department_short_name FROM departments WHERE department_id=${DEPT_ID}" 2>/dev/null)
    if [ -z "$DEPT_SHORT" ]; then
        DEPT_SHORT=$(opencad_db_query "SELECT abbreviation FROM departments WHERE department_id=${DEPT_ID}" 2>/dev/null)
    fi
    if [ -z "$DEPT_SHORT" ]; then
        DEPT_SHORT=$(opencad_db_query "SELECT short_name FROM departments WHERE department_id=${DEPT_ID}" 2>/dev/null)
    fi
else
    # Fallback: check if *any* new department was added (for partial feedback)
    LAST_DEPT_ID=$(opencad_db_query "SELECT department_id FROM departments ORDER BY department_id DESC LIMIT 1")
    if [ -n "$LAST_DEPT_ID" ]; then
         LAST_DEPT_NAME=$(opencad_db_query "SELECT department_name FROM departments WHERE department_id=${LAST_DEPT_ID}")
         echo "Debug: Last added department was '$LAST_DEPT_NAME'"
    fi
fi

# 4. Construct JSON result
# Note: JSON escaping is handled manually or via the helper if available. 
# Using python for safe JSON creation is more robust than cat for arbitrary strings.

python3 -c "
import json
import sys

data = {
    'initial_count': int('${INITIAL_COUNT:-0}'),
    'current_count': int('${CURRENT_COUNT:-0}'),
    'dept_found': '${DEPT_FOUND}' == 'true',
    'department': {
        'id': '${DEPT_ID}',
        'name': '''${DEPT_NAME}''',
        'short_name': '''${DEPT_SHORT}'''
    },
    'timestamp': '$(date -Iseconds)'
}
print(json.dumps(data, indent=2))
" > /tmp/task_result.json

# 5. Permission safety
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="