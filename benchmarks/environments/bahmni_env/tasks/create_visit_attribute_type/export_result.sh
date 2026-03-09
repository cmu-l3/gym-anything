#!/bin/bash
set -u

echo "=== Exporting Create Visit Attribute Type Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query OpenMRS API for the "Arrival Method" attribute type
echo "Querying OpenMRS for 'Arrival Method'..."
API_RESPONSE=$(openmrs_api_get "/visitattributetype?q=Arrival+Method&v=full")

# 2. Extract specific fields using jq
# We look for the first result that matches the name exactly
ATTR_DATA=$(echo "$API_RESPONSE" | jq -r '.results[] | select(.name == "Arrival Method") | {uuid: .uuid, name: .name, description: .description, datatypeClassname: .datatypeClassname, minOccurs: .minOccurs, maxOccurs: .maxOccurs, retired: .retired, dateCreated: .auditInfo.dateCreated}' 2>/dev/null | head -1)

# Check if we found anything
if [ -z "$ATTR_DATA" ] || [ "$ATTR_DATA" == "null" ]; then
    ATTR_FOUND="false"
    ATTR_JSON="{}"
else
    ATTR_FOUND="true"
    ATTR_JSON="$ATTR_DATA"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Check if screenshot exists
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
else
    SCREENSHOT_EXISTS="false"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "attribute_found": $ATTR_FOUND,
    "attribute_data": $ATTR_JSON,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="