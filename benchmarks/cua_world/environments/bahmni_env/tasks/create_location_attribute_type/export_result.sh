#!/bin/bash
echo "=== Exporting Create Location Attribute Type Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query OpenMRS API to find the specific attribute type by name
# We search for "Landline Extension"
echo "Querying OpenMRS for 'Landline Extension'..."
API_RESPONSE=$(openmrs_api_get "/locationattributetype?q=Landline%20Extension&v=full")

# 2. Extract details if found
# The API returns a list. We filter for exact name match in case of partial matches.
FOUND_ATTR=$(echo "$API_RESPONSE" | jq -r '.results[] | select(.name == "Landline Extension")' 2>/dev/null)

ATTR_EXISTS="false"
ATTR_NAME=""
ATTR_DESC=""
ATTR_DATATYPE=""
ATTR_MIN=""
ATTR_MAX=""
ATTR_RETIRED="false"
ATTR_UUID=""
ATTR_DATE_CREATED=""

if [ -n "$FOUND_ATTR" ] && [ "$FOUND_ATTR" != "null" ]; then
    ATTR_EXISTS="true"
    ATTR_NAME=$(echo "$FOUND_ATTR" | jq -r '.name')
    ATTR_DESC=$(echo "$FOUND_ATTR" | jq -r '.description')
    # Datatype might be returned as a classname or config
    ATTR_DATATYPE=$(echo "$FOUND_ATTR" | jq -r '.datatypeClassname // .datatypeConfig // "unknown"')
    ATTR_MIN=$(echo "$FOUND_ATTR" | jq -r '.minOccurs')
    ATTR_MAX=$(echo "$FOUND_ATTR" | jq -r '.maxOccurs')
    ATTR_RETIRED=$(echo "$FOUND_ATTR" | jq -r '.retired')
    ATTR_UUID=$(echo "$FOUND_ATTR" | jq -r '.uuid')
    ATTR_DATE_CREATED=$(echo "$FOUND_ATTR" | jq -r '.auditInfo.dateCreated // .dateCreated // ""')
else
    echo "Attribute type 'Landline Extension' not found in API response."
fi

# 3. Get total count change
INITIAL_COUNT=$(cat /tmp/initial_lat_count.txt 2>/dev/null || echo "0")
CURRENT_DATA=$(openmrs_api_get "/locationattributetype?v=default")
CURRENT_COUNT=$(echo "$CURRENT_DATA" | jq '.results | length' 2>/dev/null || echo "0")

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "attribute_exists": $ATTR_EXISTS,
    "attribute_details": {
        "name": "$ATTR_NAME",
        "description": "$ATTR_DESC",
        "datatype": "$ATTR_DATATYPE",
        "min_occurs": "$ATTR_MIN",
        "max_occurs": "$ATTR_MAX",
        "retired": $ATTR_RETIRED,
        "uuid": "$ATTR_UUID",
        "date_created": "$ATTR_DATE_CREATED"
    },
    "counts": {
        "initial": $INITIAL_COUNT,
        "current": $CURRENT_COUNT
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="