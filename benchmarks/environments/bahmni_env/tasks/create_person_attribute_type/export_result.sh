#!/bin/bash
echo "=== Exporting Create Person Attribute Type Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_pat_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query OpenMRS API for current state
echo "Querying OpenMRS for Person Attribute Types..."

# 1. Get all attribute types to check count
ALL_TYPES_JSON=$(openmrs_api_get "/personattributetype?v=default&limit=100")
CURRENT_COUNT=$(echo "$ALL_TYPES_JSON" | jq '.results | length')

# 2. Search specifically for "Preferred Language"
# We fetch 'full' view to see description, format, searchable status, and audit info
TARGET_ATTR_JSON=$(openmrs_api_get "/personattributetype?q=Preferred+Language&v=full")

# Extract details if found
# We use jq to find the exact match on name (case-insensitive) to be safe
ATTR_DETAILS=$(echo "$TARGET_ATTR_JSON" | jq -r '.results[] | select(.name | test("(?i)^Preferred Language$"))')

FOUND="false"
ATTR_UUID=""
ATTR_NAME=""
ATTR_FORMAT=""
ATTR_DESC=""
ATTR_SEARCHABLE="false"
ATTR_RETIRED="true"
DATE_CREATED=""

if [ -n "$ATTR_DETAILS" ] && [ "$ATTR_DETAILS" != "null" ]; then
    FOUND="true"
    ATTR_UUID=$(echo "$ATTR_DETAILS" | jq -r '.uuid')
    ATTR_NAME=$(echo "$ATTR_DETAILS" | jq -r '.name')
    ATTR_FORMAT=$(echo "$ATTR_DETAILS" | jq -r '.format')
    ATTR_DESC=$(echo "$ATTR_DETAILS" | jq -r '.description')
    ATTR_SEARCHABLE=$(echo "$ATTR_DETAILS" | jq -r '.searchable')
    ATTR_RETIRED=$(echo "$ATTR_DETAILS" | jq -r '.retired')
    DATE_CREATED=$(echo "$ATTR_DETAILS" | jq -r '.auditInfo.dateCreated // ""')
fi

# Check if browser is running
BROWSER_RUNNING=$(pgrep -f "epiphany" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "browser_running": $BROWSER_RUNNING,
    "attribute_found": $FOUND,
    "attribute_details": {
        "uuid": "$ATTR_UUID",
        "name": "$ATTR_NAME",
        "format": "$ATTR_FORMAT",
        "description": $(echo "$ATTR_DESC" | jq -R .),
        "searchable": $ATTR_SEARCHABLE,
        "retired": $ATTR_RETIRED,
        "date_created": "$DATE_CREATED"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="