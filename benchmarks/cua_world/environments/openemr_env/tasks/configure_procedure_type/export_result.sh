#!/bin/bash
# Export script for Configure Procedure Type Task

echo "=== Exporting Configure Procedure Type Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial values
INITIAL_MAX_ID=$(cat /tmp/initial_max_proc_id 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_proc_count 2>/dev/null || echo "0")

# Get current procedure type count
CURRENT_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_type" 2>/dev/null || echo "0")
echo "Procedure type count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Query for HbA1c procedure type (multiple search patterns)
echo ""
echo "=== Searching for HbA1c procedure type ==="

# Search for procedure order (type='ord') matching HbA1c criteria
HBA1C_ORDER=$(openemr_query "SELECT procedure_type_id, parent, name, procedure_type, procedure_code, standard_code, description, units, \`range\`, seq FROM procedure_type WHERE (LOWER(name) LIKE '%hba1c%' OR LOWER(name) LIKE '%a1c%' OR LOWER(name) LIKE '%hemoglobin a%' OR LOWER(name) LIKE '%glyco%' OR procedure_code = '83036' OR standard_code LIKE '%4548%') AND procedure_type IN ('ord', 'res', 'grp') ORDER BY procedure_type_id DESC LIMIT 5" 2>/dev/null)

echo "HbA1c-related procedures found:"
echo "$HBA1C_ORDER"

# Parse the most relevant procedure order
PROC_FOUND="false"
PROC_ID=""
PROC_PARENT=""
PROC_NAME=""
PROC_TYPE=""
PROC_CODE=""
PROC_STD_CODE=""
PROC_DESC=""
PROC_UNITS=""
PROC_RANGE=""

# Look specifically for an 'ord' (orderable) type first
ORD_RECORD=$(openemr_query "SELECT procedure_type_id, parent, name, procedure_type, procedure_code, standard_code, description, units, \`range\` FROM procedure_type WHERE (LOWER(name) LIKE '%hba1c%' OR LOWER(name) LIKE '%a1c%' OR LOWER(name) LIKE '%hemoglobin a%' OR procedure_code = '83036') AND procedure_type = 'ord' ORDER BY procedure_type_id DESC LIMIT 1" 2>/dev/null)

if [ -n "$ORD_RECORD" ]; then
    PROC_FOUND="true"
    PROC_ID=$(echo "$ORD_RECORD" | cut -f1)
    PROC_PARENT=$(echo "$ORD_RECORD" | cut -f2)
    PROC_NAME=$(echo "$ORD_RECORD" | cut -f3)
    PROC_TYPE=$(echo "$ORD_RECORD" | cut -f4)
    PROC_CODE=$(echo "$ORD_RECORD" | cut -f5)
    PROC_STD_CODE=$(echo "$ORD_RECORD" | cut -f6)
    PROC_DESC=$(echo "$ORD_RECORD" | cut -f7)
    PROC_UNITS=$(echo "$ORD_RECORD" | cut -f8)
    PROC_RANGE=$(echo "$ORD_RECORD" | cut -f9)
    
    echo ""
    echo "Found HbA1c procedure order:"
    echo "  ID: $PROC_ID"
    echo "  Parent: $PROC_PARENT"
    echo "  Name: $PROC_NAME"
    echo "  Type: $PROC_TYPE"
    echo "  CPT Code: $PROC_CODE"
    echo "  Standard Code: $PROC_STD_CODE"
    echo "  Description: $PROC_DESC"
else
    echo "No HbA1c procedure order (type='ord') found"
fi

# Check for result type (type='res') associated with the order
RESULT_FOUND="false"
RESULT_ID=""
RESULT_NAME=""
RESULT_UNITS=""
RESULT_RANGE=""

if [ -n "$PROC_ID" ]; then
    RES_RECORD=$(openemr_query "SELECT procedure_type_id, name, units, \`range\` FROM procedure_type WHERE parent = $PROC_ID AND procedure_type = 'res' LIMIT 1" 2>/dev/null)
    
    if [ -n "$RES_RECORD" ]; then
        RESULT_FOUND="true"
        RESULT_ID=$(echo "$RES_RECORD" | cut -f1)
        RESULT_NAME=$(echo "$RES_RECORD" | cut -f2)
        RESULT_UNITS=$(echo "$RES_RECORD" | cut -f3)
        RESULT_RANGE=$(echo "$RES_RECORD" | cut -f4)
        
        echo ""
        echo "Found associated result type:"
        echo "  ID: $RESULT_ID"
        echo "  Name: $RESULT_NAME"
        echo "  Units: $RESULT_UNITS"
        echo "  Range: $RESULT_RANGE"
    fi
fi

# If no 'ord' found, check for any matching record
if [ "$PROC_FOUND" = "false" ] && [ -n "$HBA1C_ORDER" ]; then
    PROC_FOUND="true"
    PROC_ID=$(echo "$HBA1C_ORDER" | head -1 | cut -f1)
    PROC_PARENT=$(echo "$HBA1C_ORDER" | head -1 | cut -f2)
    PROC_NAME=$(echo "$HBA1C_ORDER" | head -1 | cut -f3)
    PROC_TYPE=$(echo "$HBA1C_ORDER" | head -1 | cut -f4)
    PROC_CODE=$(echo "$HBA1C_ORDER" | head -1 | cut -f5)
    PROC_STD_CODE=$(echo "$HBA1C_ORDER" | head -1 | cut -f6)
    PROC_DESC=$(echo "$HBA1C_ORDER" | head -1 | cut -f7)
    echo "Found partial match (not 'ord' type): ID=$PROC_ID, Name=$PROC_NAME, Type=$PROC_TYPE"
fi

# Check if procedure was created after task start (anti-gaming)
CREATED_DURING_TASK="false"
if [ -n "$PROC_ID" ] && [ "$PROC_ID" -gt "$INITIAL_MAX_ID" ]; then
    CREATED_DURING_TASK="true"
    echo "Procedure ID $PROC_ID > initial max $INITIAL_MAX_ID - created during task"
elif [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    CREATED_DURING_TASK="true"
    echo "Procedure count increased ($INITIAL_COUNT -> $CURRENT_COUNT) - new records created"
fi

# Validate specific fields
CODE_CORRECT="false"
if [ "$PROC_CODE" = "83036" ]; then
    CODE_CORRECT="true"
fi

STD_CODE_SET="false"
if [ -n "$PROC_STD_CODE" ] && [ "$PROC_STD_CODE" != "NULL" ]; then
    STD_CODE_SET="true"
    # Check if it's the expected LOINC code
    if echo "$PROC_STD_CODE" | grep -qi "4548"; then
        echo "Standard code matches expected LOINC: $PROC_STD_CODE"
    fi
fi

DESC_POPULATED="false"
if [ -n "$PROC_DESC" ] && [ "$PROC_DESC" != "NULL" ] && [ ${#PROC_DESC} -gt 3 ]; then
    DESC_POPULATED="true"
fi

# Escape special characters for JSON
PROC_NAME_ESC=$(echo "$PROC_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')
PROC_DESC_ESC=$(echo "$PROC_DESC" | sed 's/"/\\"/g' | tr '\n' ' ')
RESULT_NAME_ESC=$(echo "$RESULT_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')
RESULT_RANGE_ESC=$(echo "$RESULT_RANGE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/proc_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_max_proc_id": $INITIAL_MAX_ID,
    "initial_proc_count": $INITIAL_COUNT,
    "current_proc_count": $CURRENT_COUNT,
    "procedure_found": $PROC_FOUND,
    "created_during_task": $CREATED_DURING_TASK,
    "procedure": {
        "id": "$PROC_ID",
        "parent": "$PROC_PARENT",
        "name": "$PROC_NAME_ESC",
        "type": "$PROC_TYPE",
        "procedure_code": "$PROC_CODE",
        "standard_code": "$PROC_STD_CODE",
        "description": "$PROC_DESC_ESC"
    },
    "result_type_found": $RESULT_FOUND,
    "result_type": {
        "id": "$RESULT_ID",
        "name": "$RESULT_NAME_ESC",
        "units": "$RESULT_UNITS",
        "range": "$RESULT_RANGE_ESC"
    },
    "validation": {
        "cpt_code_correct": $CODE_CORRECT,
        "standard_code_set": $STD_CODE_SET,
        "description_populated": $DESC_POPULATED
    },
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/configure_procedure_result.json 2>/dev/null || sudo rm -f /tmp/configure_procedure_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_procedure_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_procedure_result.json
chmod 666 /tmp/configure_procedure_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_procedure_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/configure_procedure_result.json"
cat /tmp/configure_procedure_result.json
echo ""
echo "=== Export Complete ==="