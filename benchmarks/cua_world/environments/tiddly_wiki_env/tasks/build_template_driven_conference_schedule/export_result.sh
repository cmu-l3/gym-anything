#!/bin/bash
echo "=== Exporting Conference Schedule result ==="

source /workspace/scripts/task_utils.sh

# Record end state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TEMPLATE_TITLE="SessionTemplate"
DASHBOARD_TITLE="My Conference Schedule"
TARGET_TAG="MySchedule"

# Get Template Data
TEMPLATE_EXISTS=$(tiddler_exists "$TEMPLATE_TITLE")
TEMPLATE_TEXT=""
if [ "$TEMPLATE_EXISTS" = "true" ]; then
    TEMPLATE_TEXT=$(get_tiddler_text "$TEMPLATE_TITLE")
fi

# Get Dashboard Data
DASHBOARD_EXISTS=$(tiddler_exists "$DASHBOARD_TITLE")
DASHBOARD_TEXT=""
DASHBOARD_TAGS=""
if [ "$DASHBOARD_EXISTS" = "true" ]; then
    DASHBOARD_TEXT=$(get_tiddler_text "$DASHBOARD_TITLE")
    DASHBOARD_TAGS=$(get_tiddler_field "$DASHBOARD_TITLE" "tags")
fi

# Get Tags for the Target Sessions
get_tags() {
    local title="$1"
    if [ "$(tiddler_exists "$title")" = "true" ]; then
        get_tiddler_field "$title" "tags"
    else
        echo ""
    fi
}

MATRIX_TAGS=$(get_tags "Matrix 2.0")
WAYLAND_TAGS=$(get_tags "The State of Wayland")
OSM_TAGS=$(get_tags "OpenStreetMap in 2024")
PG_TAGS=$(get_tags "PostgreSQL 16 Features")

# Check for extra tagged tiddlers (anti-gaming)
TOTAL_TAGGED=$(find_tiddlers_with_tag "$TARGET_TAG" | wc -l)

# Safely construct JSON using jq (handles all wikitext escaping naturally)
jq -n \
  --arg template_exists "$TEMPLATE_EXISTS" \
  --arg template_text "$TEMPLATE_TEXT" \
  --arg dashboard_exists "$DASHBOARD_EXISTS" \
  --arg dashboard_text "$DASHBOARD_TEXT" \
  --arg dashboard_tags "$DASHBOARD_TAGS" \
  --arg matrix_tags "$MATRIX_TAGS" \
  --arg wayland_tags "$WAYLAND_TAGS" \
  --arg osm_tags "$OSM_TAGS" \
  --arg pg_tags "$PG_TAGS" \
  --arg total_tagged "$TOTAL_TAGGED" \
  '{
    "template_exists": ($template_exists == "true"),
    "template_text": $template_text,
    "dashboard_exists": ($dashboard_exists == "true"),
    "dashboard_text": $dashboard_text,
    "dashboard_tags": $dashboard_tags,
    "matrix_tags": $matrix_tags,
    "wayland_tags": $wayland_tags,
    "osm_tags": $osm_tags,
    "pg_tags": $pg_tags,
    "total_tagged": ($total_tagged | tonumber)
  }' > /tmp/schedule_result.json

cat /tmp/schedule_result.json
echo "=== Export complete ==="