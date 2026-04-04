#!/bin/bash
echo "=== Exporting Triage Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the database for the request status
# We look for the specific subject
REQUEST_SUBJECT="Urgent: Payroll export failing"

# Tables (Postgres schemas in SDP can be tricky, using 'public' usually)
# workorder: main table
# workorderstates: contains IDs for category, etc.
# categorydefinition: category names
# subcategorydefinition: subcategory names
# queuedefinition: group names (queue = group)
# prioritydefinition: priority names

SQL_QUERY="
SELECT 
    wo.title,
    cd.categoryname,
    scd.name as subcategoryname,
    pd.priorityname,
    qd.queuename,
    au.first_name as technician
FROM workorder wo
LEFT JOIN workorderstates wos ON wo.workorderid = wos.workorderid
LEFT JOIN categorydefinition cd ON wos.categoryid = cd.categoryid
LEFT JOIN subcategorydefinition scd ON wos.subcategoryid = scd.subcategoryid
LEFT JOIN prioritydefinition pd ON wos.priorityid = pd.priorityid
LEFT JOIN queuedefinition qd ON wos.queueid = qd.queueid
LEFT JOIN aaauser au ON wos.ownerid = au.user_id
WHERE wo.title LIKE '%Payroll export failing%'
LIMIT 1;
"

# Execute SQL
# We use sdp_db_exec from task_utils, but we need to format the output as JSON.
# Since sdp_db_exec returns raw text, we'll format it inside psql or parse it.
# Simplest is to get pipe-separated values and parse in bash/python.

RAW_RESULT=$(sdp_db_exec "$SQL_QUERY" "servicedesk")

echo "Raw DB Result: $RAW_RESULT"

# Parse result (Format: title|category|subcategory|priority|group|technician)
# Handle potential empty fields
IFS='|' read -r TITLE CATEGORY SUBCATEGORY PRIORITY GROUP TECHNICIAN <<< "$RAW_RESULT"

# Clean up whitespace
TITLE=$(echo "$TITLE" | xargs)
CATEGORY=$(echo "$CATEGORY" | xargs)
SUBCATEGORY=$(echo "$SUBCATEGORY" | xargs)
PRIORITY=$(echo "$PRIORITY" | xargs)
GROUP=$(echo "$GROUP" | xargs)
TECHNICIAN=$(echo "$TECHNICIAN" | xargs)

# Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "request_found": $([ -n "$TITLE" ] && echo "true" || echo "false"),
    "title": "$TITLE",
    "category": "$CATEGORY",
    "subcategory": "$SUBCATEGORY",
    "priority": "$PRIORITY",
    "group": "$GROUP",
    "technician": "$TECHNICIAN",
    "timestamp": $(date +%s)
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete:"
cat /tmp/task_result.json