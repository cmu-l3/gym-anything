#!/bin/bash
# Export script for Register Child task
# Saves all verification data to JSON file for verifier to read

echo "=== Exporting Register Child Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get initial and current tracked entity counts
INITIAL_COUNT=$(cat /tmp/initial_tracked_entity_count 2>/dev/null | tr -d ' ' || echo "0")

# Try API-based approach first (more reliable)
echo "Checking for new tracked entities via API..."
API_RESULT=$(dhis2_api "trackedEntityInstances.json?ouMode=ACCESSIBLE&program=IpHINAT79UW&fields=trackedEntityInstance,created,attributes[attribute,value]&order=created:desc&pageSize=5" 2>/dev/null)

if [ -n "$API_RESULT" ] && echo "$API_RESULT" | jq . > /dev/null 2>&1; then
    echo "API response received"
    # Extract the most recent tracked entity instances
    RECENT_TEIS=$(echo "$API_RESULT" | jq -r '.trackedEntityInstances // []')
else
    echo "API query failed, falling back to database query"
    RECENT_TEIS="[]"
fi

# Database-based fallback: query tracked entities
CURRENT_COUNT=$(dhis2_query "SELECT COUNT(*) FROM trackedentityinstance" 2>/dev/null | tr -d ' ' || echo "0")
echo "Tracked entity count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent tracked entities
echo ""
echo "=== DEBUG: Most recent tracked entities in database ==="
dhis2_query "SELECT tei.uid, tei.created, teav.value
    FROM trackedentityinstance tei
    LEFT JOIN trackedentityattributevalue teav ON tei.trackedentityinstanceid = teav.trackedentityinstanceid
    ORDER BY tei.created DESC
    LIMIT 10" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Look for the target person using case-insensitive matching
echo "Checking for tracked entity 'Aminata Kamara' (case-insensitive)..."
ENTITY_FOUND="false"
ENTITY_UID=""
ENTITY_FNAME=""
ENTITY_LNAME=""
ENTITY_DOB=""
ENTITY_SEX=""

# Try to find by attribute values in the database
# DHIS2 stores tracked entity attributes in trackedentityattributevalue
# First name and last name are stored as attribute values
ENTITY_DATA=$(dhis2_query "
    SELECT DISTINCT tei.uid, tei.created
    FROM trackedentityinstance tei
    JOIN trackedentityattributevalue teav1 ON tei.trackedentityinstanceid = teav1.trackedentityinstanceid
    JOIN trackedentityattributevalue teav2 ON tei.trackedentityinstanceid = teav2.trackedentityinstanceid
    WHERE LOWER(teav1.value) = 'aminata'
    AND LOWER(teav2.value) = 'kamara'
    ORDER BY tei.created DESC
    LIMIT 1
" 2>/dev/null | head -1)

if [ -n "$ENTITY_DATA" ]; then
    ENTITY_FOUND="true"
    ENTITY_UID=$(echo "$ENTITY_DATA" | awk '{print $1}' | tr -d ' ')
    echo "Found tracked entity: UID=$ENTITY_UID"

    # Get all attribute values for this entity
    ENTITY_FNAME="Aminata"
    ENTITY_LNAME="Kamara"

    # Try to get DOB and sex from attribute values
    ALL_ATTRS=$(dhis2_query "
        SELECT tea.name, teav.value
        FROM trackedentityattributevalue teav
        JOIN trackedentityattribute tea ON teav.trackedentityattributeid = tea.trackedentityattributeid
        JOIN trackedentityinstance tei ON teav.trackedentityinstanceid = tei.trackedentityinstanceid
        WHERE tei.uid = '$ENTITY_UID'
    " 2>/dev/null)

    echo "Attributes for entity $ENTITY_UID:"
    echo "$ALL_ATTRS"

    # Parse DOB and sex from attributes (common attribute names in DHIS2)
    ENTITY_DOB=$(echo "$ALL_ATTRS" | grep -i "date of birth\|dob\|birth date" | awk -F'|' '{print $2}' | tr -d ' ' | head -1)
    ENTITY_SEX=$(echo "$ALL_ATTRS" | grep -i "sex\|gender" | awk -F'|' '{print $2}' | tr -d ' ' | head -1)
else
    echo "Exact name match not found, checking for any new tracked entities..."
    # Check if any new entities were added
    NEW_ENTITY=$(dhis2_query "
        SELECT tei.uid, tei.created
        FROM trackedentityinstance tei
        ORDER BY tei.created DESC
        LIMIT 1
    " 2>/dev/null | head -1)

    if [ -n "$NEW_ENTITY" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ] 2>/dev/null; then
        ENTITY_UID=$(echo "$NEW_ENTITY" | awk '{print $1}' | tr -d ' ')
        echo "Found new tracked entity (not matching expected name): UID=$ENTITY_UID"

        # Get attributes
        ALL_ATTRS=$(dhis2_query "
            SELECT tea.name, teav.value
            FROM trackedentityattributevalue teav
            JOIN trackedentityattribute tea ON teav.trackedentityattributeid = tea.trackedentityattributeid
            JOIN trackedentityinstance tei ON teav.trackedentityinstanceid = tei.trackedentityinstanceid
            WHERE tei.uid = '$ENTITY_UID'
        " 2>/dev/null)

        echo "Attributes for new entity:"
        echo "$ALL_ATTRS"

        ENTITY_FNAME=$(echo "$ALL_ATTRS" | grep -i "first name\|given name" | awk -F'|' '{print $2}' | tr -d ' ' | head -1)
        ENTITY_LNAME=$(echo "$ALL_ATTRS" | grep -i "last name\|family name\|surname" | awk -F'|' '{print $2}' | tr -d ' ' | head -1)
        ENTITY_DOB=$(echo "$ALL_ATTRS" | grep -i "date of birth\|dob\|birth date" | awk -F'|' '{print $2}' | tr -d ' ' | head -1)
        ENTITY_SEX=$(echo "$ALL_ATTRS" | grep -i "sex\|gender" | awk -F'|' '{print $2}' | tr -d ' ' | head -1)
    fi
fi

echo "Entity found: $ENTITY_FOUND"
echo "  UID: $ENTITY_UID"
echo "  First Name: $ENTITY_FNAME"
echo "  Last Name: $ENTITY_LNAME"
echo "  DOB: $ENTITY_DOB"
echo "  Sex: $ENTITY_SEX"

# Escape special characters for JSON
ENTITY_FNAME_ESCAPED=$(echo "$ENTITY_FNAME" | sed 's/"/\\"/g')
ENTITY_LNAME_ESCAPED=$(echo "$ENTITY_LNAME" | sed 's/"/\\"/g')
ENTITY_DOB_ESCAPED=$(echo "$ENTITY_DOB" | sed 's/"/\\"/g')
ENTITY_SEX_ESCAPED=$(echo "$ENTITY_SEX" | sed 's/"/\\"/g')

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/register_child_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_tracked_entity_count": ${INITIAL_COUNT:-0},
    "current_tracked_entity_count": ${CURRENT_COUNT:-0},
    "entity_found": $ENTITY_FOUND,
    "entity": {
        "uid": "$ENTITY_UID",
        "first_name": "$ENTITY_FNAME_ESCAPED",
        "last_name": "$ENTITY_LNAME_ESCAPED",
        "dob": "$ENTITY_DOB_ESCAPED",
        "sex": "$ENTITY_SEX_ESCAPED"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/register_child_result.json 2>/dev/null || sudo rm -f /tmp/register_child_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/register_child_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/register_child_result.json
chmod 666 /tmp/register_child_result.json 2>/dev/null || sudo chmod 666 /tmp/register_child_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/register_child_result.json"
cat /tmp/register_child_result.json

echo ""
echo "=== Export Complete ==="
