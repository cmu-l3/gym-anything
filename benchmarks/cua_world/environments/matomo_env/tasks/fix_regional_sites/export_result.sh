#!/bin/bash
# Export script for Fix Regional Sites task

echo "=== Exporting Fix Regional Sites Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ── Read seeded site IDs ──────────────────────────────────────────────────
UK_ID=$(cat /tmp/regional_uk_site_id 2>/dev/null || echo "")
DE_ID=$(cat /tmp/regional_de_site_id 2>/dev/null || echo "")
JP_ID=$(cat /tmp/regional_jp_site_id 2>/dev/null || echo "")
echo "Site IDs: UK=$UK_ID DE=$DE_ID JP=$JP_ID"

# ── Read Initial Site baseline ────────────────────────────────────────────
INIT_BASELINE=$(cat /tmp/initial_site_baseline 2>/dev/null || echo "")
echo "Initial Site baseline: $INIT_BASELINE"

# ── Debug: show all relevant sites ───────────────────────────────────────
echo ""
echo "=== DEBUG: All sites ==="
matomo_query_verbose "SELECT idsite, name, currency, timezone, ecommerce FROM matomo_site ORDER BY idsite" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# ── Query current state for each regional site ────────────────────────────
query_site() {
    local site_name="$1"
    matomo_query "SELECT idsite, currency, timezone, ecommerce FROM matomo_site WHERE LOWER(name)=LOWER('$site_name') LIMIT 1" 2>/dev/null
}

UK_DATA=$(query_site "UK Fashion Store")
DE_DATA=$(query_site "German Auto Parts")
JP_DATA=$(query_site "Tokyo Electronics")

echo "UK Fashion Store:  $UK_DATA"
echo "German Auto Parts: $DE_DATA"
echo "Tokyo Electronics: $JP_DATA"

# ── Query current Initial Site state ─────────────────────────────────────
CURRENT_INIT=$(matomo_query "SELECT idsite, currency, timezone, ecommerce FROM matomo_site WHERE LOWER(name)=LOWER('Initial Site') LIMIT 1" 2>/dev/null)
echo "Initial Site current: $CURRENT_INIT"

# ── Parse individual fields ───────────────────────────────────────────────
parse_field() {
    echo "$1" | cut -f${2}
}

UK_IDSITE=$(parse_field "$UK_DATA" 1)
UK_CURRENCY=$(parse_field "$UK_DATA" 2)
UK_TIMEZONE=$(parse_field "$UK_DATA" 3)
UK_ECOMMERCE=$(parse_field "$UK_DATA" 4)

DE_IDSITE=$(parse_field "$DE_DATA" 1)
DE_CURRENCY=$(parse_field "$DE_DATA" 2)
DE_TIMEZONE=$(parse_field "$DE_DATA" 3)
DE_ECOMMERCE=$(parse_field "$DE_DATA" 4)

JP_IDSITE=$(parse_field "$JP_DATA" 1)
JP_CURRENCY=$(parse_field "$JP_DATA" 2)
JP_TIMEZONE=$(parse_field "$JP_DATA" 3)
JP_ECOMMERCE=$(parse_field "$JP_DATA" 4)

INIT_IDSITE=$(parse_field "$CURRENT_INIT" 1)
INIT_CURRENCY=$(parse_field "$CURRENT_INIT" 2)
INIT_TIMEZONE=$(parse_field "$CURRENT_INIT" 3)
INIT_ECOMMERCE=$(parse_field "$CURRENT_INIT" 4)

# ── Check Initial Site against baseline ──────────────────────────────────
INIT_BASELINE_CURRENCY=$(echo "$INIT_BASELINE" | cut -f2)
INIT_BASELINE_TIMEZONE=$(echo "$INIT_BASELINE" | cut -f3)
INIT_BASELINE_ECOMMERCE=$(echo "$INIT_BASELINE" | cut -f4)

INITIAL_SITE_MODIFIED="false"
if [ "$INIT_CURRENCY" != "$INIT_BASELINE_CURRENCY" ] || \
   [ "$INIT_TIMEZONE" != "$INIT_BASELINE_TIMEZONE" ] || \
   [ "$INIT_ECOMMERCE" != "$INIT_BASELINE_ECOMMERCE" ]; then
    INITIAL_SITE_MODIFIED="true"
    echo "WARNING: Initial Site was modified! Baseline: $INIT_BASELINE | Current: $CURRENT_INIT"
fi

# ── Write result JSON ─────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/fix_regional_sites_result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_site_modified": $INITIAL_SITE_MODIFIED,
    "initial_site_baseline": {
        "idsite": "${INIT_IDSITE}",
        "currency": "${INIT_BASELINE_CURRENCY}",
        "timezone": "${INIT_BASELINE_TIMEZONE}",
        "ecommerce": "${INIT_BASELINE_ECOMMERCE}"
    },
    "initial_site_current": {
        "currency": "${INIT_CURRENCY}",
        "timezone": "${INIT_TIMEZONE}",
        "ecommerce": "${INIT_ECOMMERCE}"
    },
    "uk_fashion_store": {
        "idsite": "${UK_IDSITE}",
        "currency": "${UK_CURRENCY}",
        "timezone": "${UK_TIMEZONE}",
        "ecommerce": "${UK_ECOMMERCE}"
    },
    "german_auto_parts": {
        "idsite": "${DE_IDSITE}",
        "currency": "${DE_CURRENCY}",
        "timezone": "${DE_TIMEZONE}",
        "ecommerce": "${DE_ECOMMERCE}"
    },
    "tokyo_electronics": {
        "idsite": "${JP_IDSITE}",
        "currency": "${JP_CURRENCY}",
        "timezone": "${JP_TIMEZONE}",
        "ecommerce": "${JP_ECOMMERCE}"
    },
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

rm -f /tmp/fix_regional_sites_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fix_regional_sites_result.json
chmod 666 /tmp/fix_regional_sites_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/fix_regional_sites_result.json"
cat /tmp/fix_regional_sites_result.json

echo ""
echo "=== Export Complete ==="
