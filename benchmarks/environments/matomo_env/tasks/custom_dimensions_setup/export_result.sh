#!/bin/bash
# Export script for Custom Dimensions Setup task

echo "=== Exporting Custom Dimensions Setup Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SITE_ID=$(cat /tmp/research_platform_site_id 2>/dev/null || echo "")
INITIAL_DIM_COUNT=$(cat /tmp/initial_dimension_count 2>/dev/null || echo "0")
INITIAL_DIM_IDS=$(cat /tmp/initial_dimension_ids 2>/dev/null || echo "")

echo "Research Platform site ID: $SITE_ID"
echo "Initial dimension count: $INITIAL_DIM_COUNT"

# ── Debug ─────────────────────────────────────────────────────────────────
echo ""
echo "=== DEBUG: Custom dimensions for site $SITE_ID ==="
matomo_query_verbose "SELECT idcustomdimension, idsite, \`index\`, scope, name, active FROM matomo_custom_dimension WHERE idsite=$SITE_ID ORDER BY scope, \`index\`" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# ── Current dimension count ───────────────────────────────────────────────
CURRENT_DIM_COUNT="0"
[ -n "$SITE_ID" ] && CURRENT_DIM_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_custom_dimension WHERE idsite=$SITE_ID" 2>/dev/null || echo "0")
echo "Current dimension count: $CURRENT_DIM_COUNT"

# ── Query each expected dimension ─────────────────────────────────────────
query_dim() {
    local site_id="$1"
    local dim_name="$2"
    local scope="$3"
    if [ -n "$site_id" ]; then
        matomo_query "SELECT idcustomdimension, \`index\`, scope, name, active FROM matomo_custom_dimension WHERE LOWER(name)=LOWER('$dim_name') AND idsite=$site_id LIMIT 1" 2>/dev/null
    fi
}

parse_dim_json() {
    local data="$1"
    local dim_name="$2"
    local expected_scope="$3"
    if [ -z "$data" ]; then
        echo "{\"found\": false, \"name\": \"$dim_name\", \"scope\": \"$expected_scope\", \"active\": \"0\"}"
        return
    fi
    local id=$(echo "$data" | cut -f1)
    local idx=$(echo "$data" | cut -f2)
    local scope=$(echo "$data" | cut -f3)
    local name=$(echo "$data" | cut -f4 | sed 's/"/\\"/g')
    local active=$(echo "$data" | cut -f5)
    echo "{\"found\": true, \"idcustomdimension\": \"$id\", \"index\": \"$idx\", \"scope\": \"$scope\", \"name\": \"$name\", \"active\": \"$active\"}"
}

DIM1=$(query_dim "$SITE_ID" "Subscription Tier" "visit")
DIM2=$(query_dim "$SITE_ID" "User Cohort" "visit")
DIM3=$(query_dim "$SITE_ID" "Traffic Source Detail" "visit")
DIM4=$(query_dim "$SITE_ID" "Page Category" "action")
DIM5=$(query_dim "$SITE_ID" "Form Interaction" "action")

echo "Subscription Tier: $DIM1"
echo "User Cohort: $DIM2"
echo "Traffic Source Detail: $DIM3"
echo "Page Category: $DIM4"
echo "Form Interaction: $DIM5"

DIM1_JSON=$(parse_dim_json "$DIM1" "Subscription Tier" "visit")
DIM2_JSON=$(parse_dim_json "$DIM2" "User Cohort" "visit")
DIM3_JSON=$(parse_dim_json "$DIM3" "Traffic Source Detail" "visit")
DIM4_JSON=$(parse_dim_json "$DIM4" "Page Category" "action")
DIM5_JSON=$(parse_dim_json "$DIM5" "Form Interaction" "action")

# ── Write result JSON ─────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/custom_dimensions_setup_result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "site_id": "${SITE_ID}",
    "initial_dimension_count": ${INITIAL_DIM_COUNT:-0},
    "current_dimension_count": ${CURRENT_DIM_COUNT:-0},
    "initial_dimension_ids": "$(echo "$INITIAL_DIM_IDS" | sed 's/"/\\"/g')",
    "dimensions": {
        "subscription_tier": $DIM1_JSON,
        "user_cohort": $DIM2_JSON,
        "traffic_source_detail": $DIM3_JSON,
        "page_category": $DIM4_JSON,
        "form_interaction": $DIM5_JSON
    },
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

rm -f /tmp/custom_dimensions_setup_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/custom_dimensions_setup_result.json
chmod 666 /tmp/custom_dimensions_setup_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/custom_dimensions_setup_result.json"
cat /tmp/custom_dimensions_setup_result.json

echo ""
echo "=== Export Complete ==="
