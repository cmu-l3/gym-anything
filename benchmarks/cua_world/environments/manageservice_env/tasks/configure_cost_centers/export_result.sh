#!/bin/bash
echo "=== Exporting Configure Cost Centers result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# DATA EXTRACTION
# ==============================================================================
# We need to verify:
# 1. The Cost Centers exist with correct Name and Code
# 2. The Departments are linked to these Cost Centers

# Helper to escape JSON strings
json_escape() {
    echo "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

# Fetch Cost Centers
# Query returns: name|code|id
CC_DATA=$(sdp_db_exec "SELECT cost_center_name, cost_center_code, cost_center_id FROM CostCenter WHERE cost_center_name IN ('Engineering CC', 'Sales CC', 'Marketing CC');")

# Fetch Department Links
# Query returns: dept_name|cost_center_name
# We join DepartmentDefinition with CostCenter
DEPT_LINKS=$(sdp_db_exec "SELECT d.dept_name, c.cost_center_name FROM DepartmentDefinition d LEFT JOIN CostCenter c ON d.cost_center_id = c.cost_center_id WHERE d.dept_name IN ('Engineering', 'Sales', 'Marketing');")

# Construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "cost_centers_found": [
EOF

# Parse CC_DATA (Postgres -A output is pipe separated)
# Example: Engineering CC|CC-ENG-01|301
while IFS='|' read -r name code id; do
    if [ -n "$name" ]; then
        cat >> "$TEMP_JSON" << ITEM
        {
            "name": "$(echo "$name" | sed 's/"/\\"/g')",
            "code": "$(echo "$code" | sed 's/"/\\"/g')",
            "id": "$id"
        },
ITEM
    fi
done <<< "$CC_DATA"

# Remove trailing comma if items exist, close array
sed -i '$ s/,$//' "$TEMP_JSON"
cat >> "$TEMP_JSON" << EOF
    ],
    "department_links": [
EOF

# Parse DEPT_LINKS
# Example: Engineering|Engineering CC
while IFS='|' read -r dept cc_name; do
    if [ -n "$dept" ]; then
        # Handle NULL cc_name
        if [ -z "$cc_name" ]; then cc_name="null"; fi
        cat >> "$TEMP_JSON" << ITEM
        {
            "department": "$(echo "$dept" | sed 's/"/\\"/g')",
            "linked_cc": "$(echo "$cc_name" | sed 's/"/\\"/g')"
        },
ITEM
    fi
done <<< "$DEPT_LINKS"

# Remove trailing comma, close array and object
sed -i '$ s/,$//' "$TEMP_JSON"
cat >> "$TEMP_JSON" << EOF
    ],
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result data:"
cat /tmp/task_result.json
echo "=== Export complete ==="