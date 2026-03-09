#!/bin/bash
# Export script for Spec-Based Goals task

echo "=== Exporting Spec-Based Goals Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SITE_ID=$(cat /tmp/sportsfit_site_id 2>/dev/null || echo "")
INITIAL_GOAL_COUNT=$(cat /tmp/initial_goal_count_sportsfit 2>/dev/null || echo "0")
INITIAL_GOAL_IDS=$(cat /tmp/initial_goal_ids_sportsfit 2>/dev/null || echo "")

echo "SportsFit Shop site ID: $SITE_ID"
echo "Initial goal count: $INITIAL_GOAL_COUNT"

# ── Debug ─────────────────────────────────────────────────────────────────
echo ""
echo "=== DEBUG: All goals for site $SITE_ID ==="
matomo_query_verbose "SELECT idgoal, idsite, name, match_attribute, pattern_type, pattern, revenue, deleted FROM matomo_goal WHERE idsite=$SITE_ID ORDER BY idgoal" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# ── Current counts ────────────────────────────────────────────────────────
CURRENT_GOAL_COUNT="0"
[ -n "$SITE_ID" ] && CURRENT_GOAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0" 2>/dev/null || echo "0")
echo "Current goal count: $CURRENT_GOAL_COUNT"

# ── Query each expected goal ──────────────────────────────────────────────
query_goal() {
    local site_id="$1"
    local goal_name="$2"
    if [ -n "$site_id" ]; then
        matomo_query "SELECT idgoal, idsite, name, match_attribute, pattern_type, pattern, revenue
            FROM matomo_goal
            WHERE LOWER(TRIM(name))=LOWER('$goal_name') AND idsite=$site_id AND deleted=0
            ORDER BY idgoal DESC LIMIT 1" 2>/dev/null
    fi
}

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

format_goal_json() {
    local data="$1"
    local goal_name="$2"
    if [ -z "$data" ]; then
        echo "{\"found\": false, \"name\": \"$(escape_json "$goal_name")\"}"
        return
    fi
    local id=$(echo "$data" | cut -f1)
    local idsite=$(echo "$data" | cut -f2)
    local name=$(escape_json "$(echo "$data" | cut -f3)")
    local match_attr=$(echo "$data" | cut -f4)
    local ptype=$(echo "$data" | cut -f5)
    local pattern=$(escape_json "$(echo "$data" | cut -f6)")
    local revenue=$(echo "$data" | cut -f7)
    echo "{\"found\": true, \"idgoal\": \"$id\", \"idsite\": \"$idsite\", \"name\": \"$name\", \"match_attribute\": \"$match_attr\", \"pattern_type\": \"$ptype\", \"pattern\": \"$pattern\", \"revenue\": \"$revenue\"}"
}

G1=$(query_goal "$SITE_ID" "Product Page View")
G2=$(query_goal "$SITE_ID" "Add to Cart")
G3=$(query_goal "$SITE_ID" "Checkout Started")
G4=$(query_goal "$SITE_ID" "Purchase Confirmation")

echo "Product Page View: $G1"
echo "Add to Cart: $G2"
echo "Checkout Started: $G3"
echo "Purchase Confirmation: $G4"

G1_JSON=$(format_goal_json "$G1" "Product Page View")
G2_JSON=$(format_goal_json "$G2" "Add to Cart")
G3_JSON=$(format_goal_json "$G3" "Checkout Started")
G4_JSON=$(format_goal_json "$G4" "Purchase Confirmation")

# ── Write result JSON ─────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/spec_based_goals_result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "site_id": "${SITE_ID}",
    "initial_goal_count": ${INITIAL_GOAL_COUNT:-0},
    "current_goal_count": ${CURRENT_GOAL_COUNT:-0},
    "initial_goal_ids": "$(escape_json "$INITIAL_GOAL_IDS")",
    "goals": {
        "product_page_view": $G1_JSON,
        "add_to_cart": $G2_JSON,
        "checkout_started": $G3_JSON,
        "purchase_confirmation": $G4_JSON
    },
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

rm -f /tmp/spec_based_goals_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/spec_based_goals_result.json
chmod 666 /tmp/spec_based_goals_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/spec_based_goals_result.json"
cat /tmp/spec_based_goals_result.json

echo ""
echo "=== Export Complete ==="
