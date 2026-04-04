#!/bin/bash
# Export script for create_change_template task

echo "=== Exporting Create Change Template Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the created template
# We join with lookup tables to get human-readable names
echo "Querying database for template..."

# Construct SQL to fetch template details as a pipe-separated string
# Note: Using COALESCE to handle potential nulls
SQL_QUERY="
SELECT 
    ct.templatename, 
    COALESCE(type.typename, 'NULL') as type,
    COALESCE(imp.name, 'NULL') as impact,
    COALESCE(urg.name, 'NULL') as urgency,
    COALESCE(r.name, 'NULL') as reason,
    COALESCE(ct.description, '') as description,
    COALESCE(ct.rolloutplan, '') as rollout,
    COALESCE(ct.backoutplan, '') as backout,
    ct.createdtime
FROM changetemplate ct
LEFT JOIN changetype type ON ct.changetypeid = type.typeid
LEFT JOIN impact imp ON ct.impactid = imp.impactid
LEFT JOIN urgency urg ON ct.urgencyid = urg.urgencyid
LEFT JOIN reasonforchange r ON ct.reasonid = r.reasonid
WHERE ct.templatename = 'Weekly Server Patching';
"

# Execute query
# We use a custom delimiter (e.g., |#|) to avoid issues with text content
DB_RESULT=$(sdp_db_exec "COPY ($SQL_QUERY) TO STDOUT WITH DELIMITER '|';" 2>/dev/null)

# Check if we got a result
TEMPLATE_FOUND="false"
TEMPLATE_DATA="{}"

if [ -n "$DB_RESULT" ]; then
    TEMPLATE_FOUND="true"
    
    # Parse the pipe-separated values
    # Format: Name|Type|Impact|Urgency|Reason|Desc|Rollout|Backout|Time
    IFS='|' read -r NAME TYPE IMPACT URGENCY REASON DESC ROLLOUT BACKOUT CREATED_TIME <<< "$DB_RESULT"
    
    # Escape for JSON
    clean_json_str() {
        echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g'
    }

    J_NAME=$(clean_json_str "$NAME")
    J_TYPE=$(clean_json_str "$TYPE")
    J_IMPACT=$(clean_json_str "$IMPACT")
    J_URGENCY=$(clean_json_str "$URGENCY")
    J_REASON=$(clean_json_str "$REASON")
    J_DESC=$(clean_json_str "$DESC")
    J_ROLLOUT=$(clean_json_str "$ROLLOUT")
    J_BACKOUT=$(clean_json_str "$BACKOUT")
    
    TEMPLATE_DATA="{
        \"name\": \"$J_NAME\",
        \"type\": \"$J_TYPE\",
        \"impact\": \"$J_IMPACT\",
        \"urgency\": \"$J_URGENCY\",
        \"reason\": \"$J_REASON\",
        \"description\": \"$J_DESC\",
        \"rollout_plan\": \"$J_ROLLOUT\",
        \"backout_plan\": \"$J_BACKOUT\",
        \"created_time\": \"$CREATED_TIME\"
    }"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "template_found": $TEMPLATE_FOUND,
    "template_data": $TEMPLATE_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="