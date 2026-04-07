#!/bin/bash
# Export script for Create Audience Segments task

echo "=== Exporting Create Audience Segments Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_segment_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_segment WHERE deleted=0" 2>/dev/null || echo "0")
INITIAL_IDS=$(cat /tmp/initial_segment_ids 2>/dev/null || echo "")

echo "Segments: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Helper function to query segment by name
get_segment_json() {
    local name="$1"
    # Query returns: idsegment, name, definition, enable_all_users, unix_timestamp(ts_created)
    local data=$(matomo_query "SELECT idsegment, name, definition, enable_all_users, UNIX_TIMESTAMP(ts_created) 
                               FROM matomo_segment 
                               WHERE LOWER(name)=LOWER('$name') AND deleted=0 
                               ORDER BY idsegment DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$data" ]; then
        local id=$(echo "$data" | cut -f1)
        local n=$(echo "$data" | cut -f2)
        local def=$(echo "$data" | cut -f3)
        local vis=$(echo "$data" | cut -f4)
        local ts=$(echo "$data" | cut -f5)
        
        # Check if created during task (timestamp check or new ID check)
        local new="false"
        if [ "$ts" -ge "$TASK_START" ]; then
            new="true"
        elif [ -z "$INITIAL_IDS" ]; then
             new="true"
        elif ! echo ",$INITIAL_IDS," | grep -q ",$id,"; then
             new="true"
        fi

        # Escape for JSON
        n=$(echo "$n" | sed 's/"/\\"/g')
        def=$(echo "$def" | sed 's/"/\\"/g')
        
        echo "{\"found\": true, \"id\": \"$id\", \"name\": \"$n\", \"definition\": \"$def\", \"visibility\": \"$vis\", \"created_ts\": $ts, \"is_new\": $new}"
    else
        echo "{\"found\": false}"
    fi
}

# Fetch the two specific segments
SEG1_JSON=$(get_segment_json "High-Value Desktop Users")
SEG2_JSON=$(get_segment_json "Bounced Mobile Visitors")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/segments_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "segment_1": $SEG1_JSON,
    "segment_2": $SEG2_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
rm -f /tmp/segments_result.json 2>/dev/null || sudo rm -f /tmp/segments_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/segments_result.json
chmod 666 /tmp/segments_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/segments_result.json"
cat /tmp/segments_result.json
echo "=== Export Complete ==="