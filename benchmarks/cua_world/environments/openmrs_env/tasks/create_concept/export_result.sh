#!/bin/bash
echo "=== Exporting create_concept task results ==="
source /workspace/scripts/task_utils.sh

# Record timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query the database for the concept "Toluene Exposure"
# We need to join concept, concept_name, concept_class, concept_datatype, and concept_description
# We look for one created AFTER task start or simply the active one (since we cleared it in setup)

echo "Querying database for created concept..."

SQL_QUERY="
SELECT 
    c.concept_id,
    c.uuid,
    c.date_created,
    cc.name as class_name,
    cdt.name as datatype_name,
    cd.description
FROM concept c
JOIN concept_name cn ON c.concept_id = cn.concept_id
LEFT JOIN concept_class cc ON c.class_id = cc.concept_class_id
LEFT JOIN concept_datatype cdt ON c.datatype_id = cdt.concept_datatype_id
LEFT JOIN concept_description cd ON c.concept_id = cd.concept_id
WHERE cn.name = 'Toluene Exposure' 
  AND cn.concept_name_type = 'FULLY_SPECIFIED'
  AND c.retired = 0
ORDER BY c.date_created DESC 
LIMIT 1;
"

# Execute query and parse lines
# Using a temp file to handle potential newlines in description roughly
omrs_db_query "$SQL_QUERY" > /tmp/concept_raw.txt

CONCEPT_EXISTS="false"
CONCEPT_ID=""
CONCEPT_UUID=""
DATE_CREATED=""
CLASS_NAME=""
DATATYPE_NAME=""
DESCRIPTION=""

if [ -s /tmp/concept_raw.txt ]; then
    read -r CONCEPT_ID CONCEPT_UUID DATE_CREATED CLASS_NAME DATATYPE_NAME DESCRIPTION < /tmp/concept_raw.txt
    
    if [ -n "$CONCEPT_ID" ]; then
        CONCEPT_EXISTS="true"
        echo "Found Concept ID: $CONCEPT_ID"
    fi
fi

# 2. Check for Synonym "Methylbenzene exp" if concept exists
SYNONYM_EXISTS="false"
if [ "$CONCEPT_EXISTS" = "true" ]; then
    SYN_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM concept_name WHERE concept_id = $CONCEPT_ID AND name = 'Methylbenzene exp';")
    if [ "$SYN_COUNT" -gt 0 ]; then
        SYNONYM_EXISTS="true"
        echo "Synonym found."
    else
        echo "Synonym NOT found."
    fi
fi

# 3. Check timestamps (Anti-gaming)
# Convert MySQL datetime (e.g., 2025-10-10 10:10:10) to timestamp if needed, 
# but usually checking if it exists and was not there before is covered by setup logic.
# However, strictly checking date_created > task_start is better.
CREATED_DURING_TASK="false"
if [ -n "$DATE_CREATED" ]; then
    # Convert MySQL timestamp to epoch
    # Note: DB might be UTC or local. Assuming consistency within env.
    CREATED_TS=$(date -d "$DATE_CREATED" +%s 2>/dev/null || echo "0")
    if [ "$CREATED_TS" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "concept_exists": $CONCEPT_EXISTS,
    "concept_id": "${CONCEPT_ID}",
    "class_name": "${CLASS_NAME}",
    "datatype_name": "${DATATYPE_NAME}",
    "description": "$(echo $DESCRIPTION | sed 's/"/\\"/g')",
    "synonym_exists": $SYNONYM_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "task_start_ts": $TASK_START,
    "date_created": "${DATE_CREATED}"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="