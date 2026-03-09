#!/bin/bash
# Export script for Configure Goal task

echo "=== Exporting Configure Goal Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get goal counts
INITIAL_COUNT=$(cat /tmp/initial_goal_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_goal" 2>/dev/null || echo "0")

echo "Goal count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Expected goal details
EXPECTED_GOAL_NAME="Newsletter Signup"

# Debug: Show all goals in database
echo ""
echo "=== DEBUG: All goals in database ==="
matomo_query_verbose "SELECT idgoal, idsite, name, match_attribute, pattern_type, pattern, revenue FROM matomo_goal ORDER BY idgoal DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Query for the expected goal (case-insensitive)
echo "Searching for goal '$EXPECTED_GOAL_NAME'..."
GOAL_DATA=$(matomo_query "SELECT idgoal, idsite, name, match_attribute, pattern_type, pattern, revenue, deleted
     FROM matomo_goal
     WHERE LOWER(TRIM(name))=LOWER('$EXPECTED_GOAL_NAME') AND deleted=0
     ORDER BY idgoal DESC LIMIT 1" 2>/dev/null)

# Parse goal data
GOAL_FOUND="false"
GOAL_ID=""
GOAL_SITE_ID=""
GOAL_NAME=""
GOAL_MATCH_ATTRIBUTE=""
GOAL_PATTERN_TYPE=""
GOAL_PATTERN=""
GOAL_REVENUE="0"

if [ -n "$GOAL_DATA" ]; then
    GOAL_FOUND="true"
    GOAL_ID=$(echo "$GOAL_DATA" | cut -f1)
    GOAL_SITE_ID=$(echo "$GOAL_DATA" | cut -f2)
    GOAL_NAME=$(echo "$GOAL_DATA" | cut -f3)
    GOAL_MATCH_ATTRIBUTE=$(echo "$GOAL_DATA" | cut -f4)
    GOAL_PATTERN_TYPE=$(echo "$GOAL_DATA" | cut -f5)
    GOAL_PATTERN=$(echo "$GOAL_DATA" | cut -f6)
    GOAL_REVENUE=$(echo "$GOAL_DATA" | cut -f7)

    echo "Goal found:"
    echo "  ID: $GOAL_ID"
    echo "  Site ID: $GOAL_SITE_ID"
    echo "  Name: $GOAL_NAME"
    echo "  Match Attribute: $GOAL_MATCH_ATTRIBUTE"
    echo "  Pattern Type: $GOAL_PATTERN_TYPE"
    echo "  Pattern: $GOAL_PATTERN"
    echo "  Revenue: $GOAL_REVENUE"
else
    echo "Goal '$EXPECTED_GOAL_NAME' NOT found in database"

    # Check if any new goals were added
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        echo "Note: New goal(s) were added but not with expected name"
        NEWEST=$(matomo_query "SELECT name, pattern FROM matomo_goal WHERE deleted=0 ORDER BY idgoal DESC LIMIT 1" 2>/dev/null)
        echo "Most recent goal: $NEWEST"
    fi
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

GOAL_NAME_ESC=$(escape_json "$GOAL_NAME")
GOAL_MATCH_ATTRIBUTE_ESC=$(escape_json "$GOAL_MATCH_ATTRIBUTE")
GOAL_PATTERN_TYPE_ESC=$(escape_json "$GOAL_PATTERN_TYPE")
GOAL_PATTERN_ESC=$(escape_json "$GOAL_PATTERN")

# Determine if created during task (use ID-based anti-gaming + count change)
CREATED_DURING_TASK="false"
INITIAL_IDS=$(cat /tmp/initial_goal_ids 2>/dev/null || echo "")

if [ "$GOAL_FOUND" = "true" ] && [ -n "$GOAL_ID" ]; then
    # Check if the goal ID is new (not in the initial IDs list)
    IS_NEW_ID="false"
    if [ -z "$INITIAL_IDS" ]; then
        # No initial goals, so this must be new
        IS_NEW_ID="true"
    elif ! echo ",$INITIAL_IDS," | grep -q ",$GOAL_ID,"; then
        # Goal ID not in initial list
        IS_NEW_ID="true"
    fi

    if [ "$IS_NEW_ID" = "true" ]; then
        CREATED_DURING_TASK="true"
        echo "Goal was created during task execution (new ID: $GOAL_ID not in initial IDs: $INITIAL_IDS)"
    else
        echo "Warning: Goal ID $GOAL_ID existed before task (in initial IDs: $INITIAL_IDS)"
        # Also check count as secondary verification
        if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
            echo "Note: Goal count increased but found goal ID was pre-existing"
        fi
    fi
else
    echo "Goal not found or no ID available"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/configure_goal_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_goal_count": ${INITIAL_COUNT:-0},
    "current_goal_count": ${CURRENT_COUNT:-0},
    "initial_goal_ids": "$(echo "$INITIAL_IDS" | sed 's/"/\\"/g')",
    "goal_found": $GOAL_FOUND,
    "created_during_task": $CREATED_DURING_TASK,
    "goal": {
        "idgoal": "$GOAL_ID",
        "idsite": "$GOAL_SITE_ID",
        "name": "$GOAL_NAME_ESC",
        "match_attribute": "$GOAL_MATCH_ATTRIBUTE_ESC",
        "pattern_type": "$GOAL_PATTERN_TYPE_ESC",
        "pattern": "$GOAL_PATTERN_ESC",
        "revenue": "$GOAL_REVENUE"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/configure_goal_result.json 2>/dev/null || sudo rm -f /tmp/configure_goal_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_goal_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_goal_result.json
chmod 666 /tmp/configure_goal_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_goal_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/configure_goal_result.json"
cat /tmp/configure_goal_result.json

echo ""
echo "=== Export Complete ==="
