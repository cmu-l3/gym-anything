#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record end time and take final screenshot
TASK_END=$(date +%s)
take_screenshot /tmp/task_final.png ga

# ---- Extract Data from Sentrifugo Database ----

# 1. Organization General Info
ORG_DATA=$(sentrifugo_db_query "SELECT orgname, orgcode, timezone, dateformat FROM main_organization LIMIT 1;")
ORG_NAME=$(echo "$ORG_DATA" | cut -f1)
ORG_CODE=$(echo "$ORG_DATA" | cut -f2)
ORG_TZ=$(echo "$ORG_DATA" | cut -f3)
ORG_DATEFMT=$(echo "$ORG_DATA" | cut -f4)

# 2. London HQ Location
LONDON_DATA=$(sentrifugo_db_query "SELECT locationname, city, isactive FROM main_locations WHERE locationname LIKE '%London%' ORDER BY id DESC LIMIT 1;")
LONDON_EXISTS="false"
LONDON_ACTIVE="0"
LONDON_CITY=""
LONDON_NAME=""

if [ -n "$LONDON_DATA" ]; then
    LONDON_EXISTS="true"
    LONDON_NAME=$(echo "$LONDON_DATA" | cut -f1)
    LONDON_CITY=$(echo "$LONDON_DATA" | cut -f2)
    LONDON_ACTIVE=$(echo "$LONDON_DATA" | cut -f3)
fi

# 3. Legacy New York HQ Location
NY_DATA=$(sentrifugo_db_query "SELECT isactive FROM main_locations WHERE locationname='New York HQ' LIMIT 1;")
NY_EXISTS="false"
NY_ACTIVE="1"

if [ -n "$NY_DATA" ]; then
    NY_EXISTS="true"
    NY_ACTIVE=$(echo "$NY_DATA" | tr -d '[:space:]')
fi

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/rebranding_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_end": $TASK_END,
    "org_data": {
        "orgname": "$(echo "$ORG_NAME" | sed 's/"/\\"/g')",
        "orgcode": "$(echo "$ORG_CODE" | sed 's/"/\\"/g')",
        "timezone": "$(echo "$ORG_TZ" | sed 's/"/\\"/g')",
        "dateformat": "$(echo "$ORG_DATEFMT" | sed 's/"/\\"/g')"
    },
    "new_hq": {
        "exists": $LONDON_EXISTS,
        "name": "$(echo "$LONDON_NAME" | sed 's/"/\\"/g')",
        "city": "$(echo "$LONDON_CITY" | sed 's/"/\\"/g')",
        "isactive": "$LONDON_ACTIVE"
    },
    "legacy_hq": {
        "exists": $NY_EXISTS,
        "isactive": "$NY_ACTIVE"
    }
}
EOF

# Save result with correct permissions
rm -f /tmp/rebranding_result.json 2>/dev/null || sudo rm -f /tmp/rebranding_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/rebranding_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/rebranding_result.json
chmod 666 /tmp/rebranding_result.json 2>/dev/null || sudo chmod 666 /tmp/rebranding_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/rebranding_result.json"
cat /tmp/rebranding_result.json
echo "=== Export Complete ==="