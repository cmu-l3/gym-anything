#!/bin/bash
# Export script for setup_community_events_calendar task
echo "=== Exporting setup_community_events_calendar result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Check if plugin is active
PLUGIN_ACTIVE="false"
if wp plugin is-active the-events-calendar --allow-root 2>/dev/null; then
    PLUGIN_ACTIVE="true"
    echo "The Events Calendar plugin is active."
else
    echo "The Events Calendar plugin is NOT active."
fi

# 2. Check for the venue
VENUE_ID=""
if [ "$PLUGIN_ACTIVE" = "true" ]; then
    VENUE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='tribe_venue' AND post_status='publish' AND LOWER(TRIM(post_title))='downtown central library' LIMIT 1" | tr -d '\r' | tr -d '\n')
    if [ -n "$VENUE_ID" ]; then
        echo "Found Venue 'Downtown Central Library' with ID: $VENUE_ID"
    else
        echo "Venue 'Downtown Central Library' NOT found."
    fi
fi

# 3. Check for the events
get_event_json() {
    local title="$1"
    local id=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='tribe_events' AND post_status='publish' AND LOWER(TRIM(post_title))=LOWER(TRIM('$title')) LIMIT 1" | tr -d '\r' | tr -d '\n')
    
    if [ -n "$id" ]; then
        local start=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$id AND meta_key='_EventStartDate' LIMIT 1" | tr -d '\r' | tr -d '\n')
        local venue_id=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$id AND meta_key='_EventVenueID' LIMIT 1" | tr -d '\r' | tr -d '\n')
        
        # Output clean JSON fragment
        echo "{\"found\": true, \"id\": $id, \"start_date\": \"$start\", \"venue_id\": \"$venue_id\"}"
    else
        echo "{\"found\": false, \"id\": null, \"start_date\": \"\", \"venue_id\": \"\"}"
    fi
}

EVENT1_JSON='{"found": false}'
EVENT2_JSON='{"found": false}'
EVENT3_JSON='{"found": false}'

if [ "$PLUGIN_ACTIVE" = "true" ]; then
    EVENT1_JSON=$(get_event_json "Summer Reading Kickoff")
    EVENT2_JSON=$(get_event_json "Digital Literacy Workshop")
    EVENT3_JSON=$(get_event_json "Local Author Meet & Greet")
fi

# Get start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_VENUE_COUNT=$(cat /tmp/initial_venue_count 2>/dev/null || echo "0")
INITIAL_EVENT_COUNT=$(cat /tmp/initial_event_count 2>/dev/null || echo "0")

# Build final JSON manually
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "plugin_active": $PLUGIN_ACTIVE,
    "initial_venue_count": $INITIAL_VENUE_COUNT,
    "initial_event_count": $INITIAL_EVENT_COUNT,
    "venue": {
        "found": $(if [ -n "$VENUE_ID" ]; then echo "true"; else echo "false"; fi),
        "id": "${VENUE_ID:-null}"
    },
    "events": {
        "event1": $EVENT1_JSON,
        "event2": $EVENT2_JSON,
        "event3": $EVENT3_JSON
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="