#!/bin/bash
echo "=== Exporting build_automated_standup_generator result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/standup_final.png

# Check Template
TEMPLATE_EXISTS=$(tiddler_exists "Standup Template")
TEMPLATE_TEXT=""
if [ "$TEMPLATE_EXISTS" = "true" ]; then
    TEMPLATE_TEXT=$(get_tiddler_text "Standup Template")
fi

# Check Dashboard
DASHBOARD_EXISTS=$(tiddler_exists "Scrum Dashboard")
DASHBOARD_TEXT=""
if [ "$DASHBOARD_EXISTS" = "true" ]; then
    DASHBOARD_TEXT=$(get_tiddler_text "Scrum Dashboard")
fi

# Find today's standup
TODAY_STR=$(date +"%Y-%m-%d")
EXPECTED_TODAY_TITLE="$TODAY_STR - Daily Standup"

TODAY_EXISTS=$(tiddler_exists "$EXPECTED_TODAY_TITLE")
TODAY_TEXT=""
TODAY_TAGS=""
ACTUAL_TODAY_TITLE=""

if [ "$TODAY_EXISTS" = "true" ]; then
    TODAY_TEXT=$(get_tiddler_text "$EXPECTED_TODAY_TITLE")
    TODAY_TAGS=$(get_tiddler_field "$EXPECTED_TODAY_TITLE" "tags")
    ACTUAL_TODAY_TITLE="$EXPECTED_TODAY_TITLE"
else
    # Try to find any new tiddler with "Daily Standup" in title that isn't one of the historical ones
    for f in "$TIDDLER_DIR"/*Daily\ Standup.tid; do
        if [ -f "$f" ]; then
            TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
            if [ "$TITLE" != "2026-03-05 - Daily Standup" ] && [ "$TITLE" != "2026-03-06 - Daily Standup" ]; then
                TODAY_EXISTS="true"
                ACTUAL_TODAY_TITLE="$TITLE"
                TODAY_TEXT=$(get_tiddler_text "$TITLE")
                TODAY_TAGS=$(get_tiddler_field "$TITLE" "tags")
                break
            fi
        fi
    done
fi

# If STILL not found, just look for any tiddler containing the target string
if [ "$TODAY_EXISTS" = "false" ]; then
    for f in "$TIDDLER_DIR"/*.tid; do
        if [ -f "$f" ]; then
            if grep -qi "Configured the automated standup generator" "$f"; then
                TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
                if [ "$TITLE" != "Standup Template" ] && [ "$TITLE" != "Scrum Dashboard" ]; then
                    TODAY_EXISTS="true"
                    ACTUAL_TODAY_TITLE="$TITLE"
                    TODAY_TEXT=$(get_tiddler_text "$TITLE")
                    TODAY_TAGS=$(get_tiddler_field "$TITLE" "tags")
                    break
                fi
            fi
        fi
    done
fi

ESCAPED_TEMPLATE_TEXT=$(json_escape "$TEMPLATE_TEXT")
ESCAPED_DASHBOARD_TEXT=$(json_escape "$DASHBOARD_TEXT")
ESCAPED_TODAY_TEXT=$(json_escape "$TODAY_TEXT")
ESCAPED_TODAY_TAGS=$(json_escape "$TODAY_TAGS")
ESCAPED_TODAY_TITLE=$(json_escape "$ACTUAL_TODAY_TITLE")

JSON_RESULT=$(cat << EOF
{
    "template_exists": $TEMPLATE_EXISTS,
    "template_text": "$ESCAPED_TEMPLATE_TEXT",
    "dashboard_exists": $DASHBOARD_EXISTS,
    "dashboard_text": "$ESCAPED_DASHBOARD_TEXT",
    "today_standup_exists": $TODAY_EXISTS,
    "today_standup_title": "$ESCAPED_TODAY_TITLE",
    "today_standup_tags": "$ESCAPED_TODAY_TAGS",
    "today_standup_text": "$ESCAPED_TODAY_TEXT",
    "expected_today_str": "$TODAY_STR",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/standup_result.json"

echo "Result saved to /tmp/standup_result.json"
cat /tmp/standup_result.json
echo "=== Export complete ==="