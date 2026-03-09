#!/bin/bash
echo "=== Exporting create_drug results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_drug_count.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database directly (Primary verification source 1)
# We check for the specific drug and return details
echo "Querying Database..."
DB_RESULT=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT 
    d.drug_id, 
    d.name, 
    d.strength, 
    d.combination, 
    d.date_created,
    cn.name as concept_name
FROM drug d
JOIN concept_name cn ON d.concept_id = cn.concept_id AND cn.concept_name_type = 'FULLY_SPECIFIED'
WHERE d.name LIKE 'Amoxicillin 500mg Capsule' AND d.retired = 0;
" 2>/dev/null)

# Parse DB Result
DB_FOUND="false"
DB_NAME=""
DB_STRENGTH=""
DB_COMBINATION=""
DB_CONCEPT=""
DB_CREATED_TS=0

if [ -n "$DB_RESULT" ]; then
    DB_FOUND="true"
    # Read tab-separated values
    DB_NAME=$(echo "$DB_RESULT" | cut -f2)
    DB_STRENGTH=$(echo "$DB_RESULT" | cut -f3)
    DB_COMBINATION=$(echo "$DB_RESULT" | cut -f4)
    DB_DATE_STR=$(echo "$DB_RESULT" | cut -f5)
    DB_CONCEPT=$(echo "$DB_RESULT" | cut -f6)
    
    # Convert DB date to timestamp for comparison
    DB_CREATED_TS=$(date -d "$DB_DATE_STR" +%s 2>/dev/null || echo "0")
fi

# 3. Check API (Primary verification source 2)
echo "Querying API..."
API_RESPONSE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/drug?q=Amoxicillin&v=full")

# Save API response for debugging/parsing
echo "$API_RESPONSE" > /tmp/api_response.json

# Extract details via python
API_DETAILS=$(python3 -c "
import sys, json
try:
    data = json.load(open('/tmp/api_response.json'))
    target = None
    for result in data.get('results', []):
        if result.get('name', '').lower() == 'amoxicillin 500mg capsule' and not result.get('retired'):
            target = result
            break
    
    if target:
        print(json.dumps({
            'found': True,
            'name': target.get('name'),
            'strength': target.get('strength'),
            'combination': target.get('combination'),
            'concept_display': target.get('concept', {}).get('display', ''),
            'uuid': target.get('uuid')
        }))
    else:
        print(json.dumps({'found': False}))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_db_count": $INITIAL_COUNT,
    "db_verification": {
        "found": $DB_FOUND,
        "name": "$DB_NAME",
        "strength": "$DB_STRENGTH",
        "combination": "$DB_COMBINATION",
        "concept": "$DB_CONCEPT",
        "created_timestamp": $DB_CREATED_TS
    },
    "api_verification": $API_DETAILS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="