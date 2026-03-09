#!/bin/bash
# export_result.sh — Verify the "set_feeds_public" task
# Checks DB state and Public API access

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# -----------------------------------------------------------------------
# 1. Capture Final State
# -----------------------------------------------------------------------
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# 2. Verify Feed Status via Database
# -----------------------------------------------------------------------
# Function to check if a specific feed is public
check_feed_public() {
    local name="$1"
    local is_public
    is_public=$(db_query "SELECT public FROM feeds WHERE name='${name}' LIMIT 1" | tr -d '[:space:]')
    if [ "$is_public" = "1" ]; then echo "true"; else echo "false"; fi
}

GRID_PUBLIC=$(check_feed_public "campus_grid_power")
SOLAR_PUBLIC=$(check_feed_public "solar_array_output")
TEMP_PUBLIC=$(check_feed_public "main_hall_temperature")

echo "Feed Status: Grid=$GRID_PUBLIC, Solar=$SOLAR_PUBLIC, Temp=$TEMP_PUBLIC"

# -----------------------------------------------------------------------
# 3. Check for Unintended Changes (Anti-Gaming)
# -----------------------------------------------------------------------
# Count how many feeds are public that are NOT in our target list
UNINTENDED_COUNT=$(db_query "SELECT COUNT(*) FROM feeds WHERE public=1 AND name NOT IN ('campus_grid_power','solar_array_output','main_hall_temperature')" | tr -d '[:space:]')
UNINTENDED_COUNT=${UNINTENDED_COUNT:-0}

echo "Unintended public feeds: $UNINTENDED_COUNT"

# -----------------------------------------------------------------------
# 4. Functional Test: Access via Public API (No API Key)
# -----------------------------------------------------------------------
# Try to read 'campus_grid_power' without authentication
GRID_ID=$(db_query "SELECT id FROM feeds WHERE name='campus_grid_power' LIMIT 1" | tr -d '[:space:]')
API_ACCESS_SUCCESS="false"

if [ -n "$GRID_ID" ]; then
    # Curl without apikey parameter
    HTTP_CODE=$(curl -s -o /tmp/api_response.json -w "%{http_code}" "${EMONCMS_URL}/feed/value.json?id=${GRID_ID}")
    RESPONSE_BODY=$(cat /tmp/api_response.json)
    
    # Valid response is just a number (e.g. "42.5") or json value
    # Invalid response is usually JSON error or "false"
    
    if [ "$HTTP_CODE" = "200" ]; then
        # Check if response looks like a number
        if [[ "$RESPONSE_BODY" =~ ^[0-9]+\.?[0-9]*$ ]] || [[ "$RESPONSE_BODY" =~ ^\"[0-9]+\.?[0-9]*\"$ ]]; then
            API_ACCESS_SUCCESS="true"
        fi
    fi
    echo "Public API Check (ID=$GRID_ID): HTTP $HTTP_CODE, Body='$RESPONSE_BODY' -> Success=$API_ACCESS_SUCCESS"
fi

# -----------------------------------------------------------------------
# 5. Export to JSON
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "feed_status": {
        "campus_grid_power": $GRID_PUBLIC,
        "solar_array_output": $SOLAR_PUBLIC,
        "main_hall_temperature": $TEMP_PUBLIC
    },
    "unintended_public_feeds_count": $UNINTENDED_COUNT,
    "public_api_access_functional": $API_ACCESS_SUCCESS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="