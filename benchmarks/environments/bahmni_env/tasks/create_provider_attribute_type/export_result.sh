#!/bin/bash
echo "=== Exporting Create Provider Attribute Type Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_END_TIME=$(date +%s)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Verify via OpenMRS REST API
# We search for "National Provider Identifier"
echo "Querying OpenMRS API for the new attribute type..."
API_RESPONSE=$(openmrs_api_get "/providerattributetype?q=National&v=full")

# Save raw response for debug
echo "$API_RESPONSE" > /tmp/api_response.json

# Extract fields using Python for reliability
API_RESULT_JSON=$(python3 <<EOF
import json, sys
try:
    data = json.load(open('/tmp/api_response.json'))
    results = data.get('results', [])
    # Filter for exact name match if multiple returned
    target = next((r for r in results if r.get('name') == 'National Provider Identifier'), None)
    
    if target:
        output = {
            "found": True,
            "uuid": target.get('uuid'),
            "name": target.get('name'),
            "description": target.get('description'),
            "datatypeClassname": target.get('datatypeClassname'),
            "minOccurs": target.get('minOccurs'),
            "maxOccurs": target.get('maxOccurs'),
            "retired": target.get('retired'),
            "audit_created": target.get('auditInfo', {}).get('dateCreated')
        }
    else:
        output = {"found": False}
    print(json.dumps(output))
except Exception as e:
    print(json.dumps({"found": False, "error": str(e)}))
EOF
)

# 3. Verify via Database (Secondary Signal)
# Check directly in the MySQL database to prevent UI-only gaming
echo "Querying MySQL database..."
DB_RESULT=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e \
    "SELECT name, description, datatype, min_occurs, max_occurs, date_created FROM provider_attribute_type WHERE name='National Provider Identifier' AND retired=0 ORDER BY provider_attribute_type_id DESC LIMIT 1" 2>/dev/null)

if [ -n "$DB_RESULT" ]; then
    # Parse tab-separated output
    DB_NAME=$(echo "$DB_RESULT" | cut -f1)
    DB_DESC=$(echo "$DB_RESULT" | cut -f2)
    DB_DATATYPE=$(echo "$DB_RESULT" | cut -f3)
    DB_MIN=$(echo "$DB_RESULT" | cut -f4)
    DB_MAX=$(echo "$DB_RESULT" | cut -f5)
    DB_DATE=$(echo "$DB_RESULT" | cut -f6)
    
    DB_JSON="{\"found\": true, \"name\": \"$DB_NAME\", \"description\": \"$DB_DESC\", \"datatype\": \"$DB_DATATYPE\", \"min\": \"$DB_MIN\", \"max\": \"$DB_MAX\", \"date\": \"$DB_DATE\"}"
else
    DB_JSON="{\"found\": false}"
fi

# 4. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TIME,
    "task_end_timestamp": $TASK_END_TIME,
    "api_result": $API_RESULT_JSON,
    "db_result": $DB_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="