#!/bin/bash
# Export script for "create_custom_role" task
# Verifies role existence in DB and exports evidence

echo "=== Exporting Custom Role Result ==="
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_ROLE_COUNT=$(cat /tmp/initial_role_count.txt 2>/dev/null || echo "0")

# 3. Check Database for the specific role
echo "Querying database for 'L1 Support Analyst'..."

# Get role details if it exists
# We fetch ID, Name, Description, and Creation Time (if available in schema, otherwise inferred)
ROLE_JSON=$(sdp_db_exec "
    SELECT row_to_json(t) FROM (
        SELECT id, name, description, created_time 
        FROM AaaRole 
        WHERE name = 'L1 Support Analyst'
    ) t;" 2>/dev/null)

# 4. Get current role count
CURRENT_ROLE_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM AaaRole;" 2>/dev/null || echo "0")

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_role_count": $INITIAL_ROLE_COUNT,
    "current_role_count": $CURRENT_ROLE_COUNT,
    "role_found": $(if [ -n "$ROLE_JSON" ]; then echo "true"; else echo "false"; fi),
    "role_details": $(if [ -n "$ROLE_JSON" ]; then echo "$ROLE_JSON"; else echo "null"; fi),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save result to accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="