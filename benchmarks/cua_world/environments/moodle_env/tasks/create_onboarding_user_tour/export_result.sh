#!/bin/bash
# Export script for Create Onboarding User Tour task

echo "=== Exporting User Tour Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get baseline info
INITIAL_TOUR_COUNT=$(cat /tmp/initial_tour_count 2>/dev/null || echo "0")
CURRENT_TOUR_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_tool_usertours_tours" 2>/dev/null || echo "0")

echo "Tour count: initial=$INITIAL_TOUR_COUNT, current=$CURRENT_TOUR_COUNT"

# Search for the specific tour
# We look for the exact name or path match to identify the candidate
TOUR_DATA=$(moodle_query "SELECT id, name, pathmatch, enabled, configdata FROM mdl_tool_usertours_tours WHERE LOWER(name) LIKE '%new student dashboard guide%' OR pathmatch LIKE '/my/%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

TOUR_FOUND="false"
TOUR_ID=""
TOUR_NAME=""
TOUR_PATHMATCH=""
TOUR_ENABLED="0"
STEPS_JSON="[]"

if [ -n "$TOUR_DATA" ]; then
    TOUR_FOUND="true"
    TOUR_ID=$(echo "$TOUR_DATA" | cut -f1)
    TOUR_NAME=$(echo "$TOUR_DATA" | cut -f2)
    TOUR_PATHMATCH=$(echo "$TOUR_DATA" | cut -f3)
    TOUR_ENABLED=$(echo "$TOUR_DATA" | cut -f4)
    
    echo "Tour found: ID=$TOUR_ID, Name='$TOUR_NAME', Path='$TOUR_PATHMATCH', Enabled=$TOUR_ENABLED"

    # Get steps for this tour
    # We construct a JSON array of step objects manually or via loop
    # Query: id, targettype, targetvalue, title, configdata
    STEPS_RAW=$(moodle_query "SELECT id, targettype, targetvalue, title, configdata FROM mdl_tool_usertours_steps WHERE tourid=$TOUR_ID ORDER BY sortorder ASC" 2>/dev/null)
    
    if [ -n "$STEPS_RAW" ]; then
        # Convert tab-separated lines to JSON array
        # This is a bit complex in bash, so we'll just dump the raw string and let Python parse it
        # Actually, let's format it as a simple list of objects for the python verifier
        STEPS_JSON="["
        while IFS=$'\t' read -r sid stype svalue stitle sconfig; do
            # Escape quotes in title/value
            svalue=$(echo "$svalue" | sed 's/"/\\"/g')
            stitle=$(echo "$stitle" | sed 's/"/\\"/g')
            # sconfig is already JSON, but we need to escape it to put it inside a JSON string
            sconfig_escaped=$(echo "$sconfig" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
            
            STEPS_JSON="${STEPS_JSON}{\"id\":$sid,\"targettype\":$stype,\"targetvalue\":\"$svalue\",\"title\":\"$stitle\",\"configdata\":\"$sconfig_escaped\"},"
        done <<< "$STEPS_RAW"
        # Remove trailing comma and close bracket
        STEPS_JSON="${STEPS_JSON%,}]"
    fi
else
    echo "Target tour NOT found"
fi

# Escape values for JSON
TOUR_NAME_ESC=$(echo "$TOUR_NAME" | sed 's/"/\\"/g')
TOUR_PATHMATCH_ESC=$(echo "$TOUR_PATHMATCH" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/user_tour_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_tour_count": ${INITIAL_TOUR_COUNT:-0},
    "current_tour_count": ${CURRENT_TOUR_COUNT:-0},
    "tour_found": $TOUR_FOUND,
    "tour": {
        "id": "$TOUR_ID",
        "name": "$TOUR_NAME_ESC",
        "pathmatch": "$TOUR_PATHMATCH_ESC",
        "enabled": "$TOUR_ENABLED"
    },
    "steps": $STEPS_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/user_tour_result.json

echo ""
cat /tmp/user_tour_result.json
echo ""
echo "=== Export Complete ==="