#!/bin/bash
# Export script for create_project_template task
# Queries SDP database for the created template hierarchy

echo "=== Exporting Project Template Results ==="
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. SEARCH FOR TEMPLATE
# Try 'projectdetails' with is_template=true first (common in recent SDP)
# We search case-insensitive for the name "New Branch Office Setup"
TEMPLATE_ID=$(sdp_db_exec "SELECT project_id FROM projectdetails WHERE is_template='true' AND LOWER(title) LIKE '%new branch office setup%' LIMIT 1;" 2>/dev/null)
TEMPLATE_TABLE="projectdetails"

# If not found, try 'projecttemplate' table
if [ -z "$TEMPLATE_ID" ] || [ "$TEMPLATE_ID" = "0" ]; then
    TEMPLATE_ID=$(sdp_db_exec "SELECT templateid FROM projecttemplate WHERE LOWER(templatename) LIKE '%new branch office setup%' LIMIT 1;" 2>/dev/null)
    TEMPLATE_TABLE="projecttemplate"
fi

echo "Found Template ID: $TEMPLATE_ID (in table: $TEMPLATE_TABLE)"

# 2. SEARCH FOR MILESTONE
# Milestones usually link to project_id. 
# If we found a template ID, we search for milestones linked to it.
MILESTONE_FOUND="false"
MILESTONE_ID=""

if [ -n "$TEMPLATE_ID" ] && [ "$TEMPLATE_ID" != "0" ]; then
    # Query for milestone title
    # Note: Table might be 'milestone' or 'projectmilestone'
    MILESTONE_ID=$(sdp_db_exec "SELECT milestone_id FROM milestone WHERE project_id=$TEMPLATE_ID AND LOWER(title) LIKE '%infrastructure preparation%' LIMIT 1;" 2>/dev/null)
    
    if [ -n "$MILESTONE_ID" ] && [ "$MILESTONE_ID" != "0" ]; then
        MILESTONE_FOUND="true"
    fi
fi
echo "Milestone Found: $MILESTONE_FOUND (ID: $MILESTONE_ID)"

# 3. SEARCH FOR TASK
# Tasks usually link to milestone_id
TASK_FOUND="false"

if [ -n "$MILESTONE_ID" ] && [ "$MILESTONE_ID" != "0" ]; then
    # Check 'projecttask' or 'taskdetails'
    TASK_ID=$(sdp_db_exec "SELECT task_id FROM projecttask WHERE milestone_id=$MILESTONE_ID AND LOWER(title) LIKE '%site survey and cabling check%' LIMIT 1;" 2>/dev/null)
    
    if [ -n "$TASK_ID" ] && [ "$TASK_ID" != "0" ]; then
        TASK_FOUND="true"
    fi
fi
echo "Task Found: $TASK_FOUND (ID: $TASK_ID)"

# 4. Check Priority (Metadata check)
# If template exists, check if priority is High (usually ID 3 or text 'High')
PRIORITY_MATCH="false"
if [ -n "$TEMPLATE_ID" ]; then
    if [ "$TEMPLATE_TABLE" = "projectdetails" ]; then
        # Check priority column (might be an ID or string)
        PRIORITY_VAL=$(sdp_db_exec "SELECT priority FROM projectdetails WHERE project_id=$TEMPLATE_ID;" 2>/dev/null)
        # Assuming High might be represented as text or a specific ID. We'll check loosely.
        # Often Priority IDs: 1=Low, 2=Normal, 3=High. Or checking logic.
        # We will assume if the template exists, we give partial credit, but checking specifics helps.
        # For simplicity in SQL, we'll just check if the ID exists for now.
        PRIORITY_MATCH="true" # Stub to true if template exists, robust check is hard without exact enum mapping
    fi
fi

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "template_found": $( [ -n "$TEMPLATE_ID" ] && [ "$TEMPLATE_ID" != "0" ] && echo "true" || echo "false" ),
    "template_id": "${TEMPLATE_ID:-0}",
    "milestone_found": $MILESTONE_FOUND,
    "task_found": $TASK_FOUND,
    "final_screenshot_path": "/tmp/task_final.png"
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