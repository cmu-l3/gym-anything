#!/bin/bash
# Export script for Remediate Analytics Audit task
# Queries goals, segments, dashboard layout, and custom dimensions,
# then packages everything into a JSON result file.

echo "=== Exporting Remediate Analytics Audit Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SITE_ID=$(cat /tmp/freshcart_site_id 2>/dev/null || echo "")
INITIAL_SEGMENT_COUNT=$(cat /tmp/initial_segment_count.txt 2>/dev/null || echo "0")
INITIAL_DIM_COUNT=$(cat /tmp/initial_dimension_count.txt 2>/dev/null || echo "0")
INITIAL_GOAL_IDS=$(cat /tmp/initial_goal_ids.txt 2>/dev/null || echo "")

echo "FreshCart site ID: $SITE_ID"

# ── Debug: dump current state ─────────────────────────────────────────────
echo ""
echo "=== DEBUG: Goals for site $SITE_ID ==="
matomo_query_verbose "SELECT idgoal, name, match_attribute, pattern, pattern_type, deleted FROM matomo_goal WHERE idsite=$SITE_ID ORDER BY idgoal" 2>/dev/null
echo "=== DEBUG: Segments ==="
matomo_query_verbose "SELECT idsegment, name, definition, enable_all_users, enable_only_idsite, deleted FROM matomo_segment WHERE (enable_only_idsite=$SITE_ID OR enable_only_idsite=0) AND deleted=0 ORDER BY idsegment" 2>/dev/null
echo "=== DEBUG: Dashboard ==="
matomo_query_verbose "SELECT iddashboard, name, LEFT(layout, 200) AS layout_preview FROM matomo_user_dashboard WHERE login='admin' ORDER BY iddashboard" 2>/dev/null
echo "=== DEBUG: Custom Dimensions ==="
matomo_query_verbose "SELECT idcustomdimension, name, scope, active FROM matomo_custom_dimensions WHERE idsite=$SITE_ID ORDER BY idcustomdimension" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# ── Helper functions ──────────────────────────────────────────────────────
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
}

# ── Query goals ───────────────────────────────────────────────────────────
query_goal() {
    local site_id="$1"
    local goal_name="$2"
    if [ -n "$site_id" ]; then
        matomo_query "SELECT idgoal, name, match_attribute, pattern, pattern_type FROM matomo_goal WHERE LOWER(TRIM(name))=LOWER('$goal_name') AND idsite=$site_id AND deleted=0 ORDER BY idgoal DESC LIMIT 1" 2>/dev/null
    fi
}

format_goal_json() {
    local data="$1"
    local goal_name="$2"
    if [ -z "$data" ]; then
        echo "{\"found\": false, \"name\": \"$(escape_json "$goal_name")\"}"
        return
    fi
    local id=$(echo "$data" | cut -f1)
    local name=$(escape_json "$(echo "$data" | cut -f2)")
    local match_attr=$(echo "$data" | cut -f3)
    local pattern=$(escape_json "$(echo "$data" | cut -f4)")
    local ptype=$(echo "$data" | cut -f5 | tr -d '[:space:]')
    echo "{\"found\": true, \"idgoal\": \"$id\", \"name\": \"$name\", \"match_attribute\": \"$match_attr\", \"pattern\": \"$pattern\", \"pattern_type\": \"$ptype\"}"
}

G1=$(query_goal "$SITE_ID" "Product Page View")
G2=$(query_goal "$SITE_ID" "Add to Cart")
G3=$(query_goal "$SITE_ID" "Begin Checkout")
G4=$(query_goal "$SITE_ID" "Purchase Complete")

G1_JSON=$(format_goal_json "$G1" "Product Page View")
G2_JSON=$(format_goal_json "$G2" "Add to Cart")
G3_JSON=$(format_goal_json "$G3" "Begin Checkout")
G4_JSON=$(format_goal_json "$G4" "Purchase Complete")

echo "Goals exported."

# ── Query segments ────────────────────────────────────────────────────────
query_segment() {
    local site_id="$1"
    local seg_name="$2"
    if [ -n "$site_id" ]; then
        matomo_query "SELECT idsegment, name, definition, enable_all_users, enable_only_idsite FROM matomo_segment WHERE LOWER(TRIM(name))=LOWER('$seg_name') AND (enable_only_idsite=$site_id OR enable_only_idsite=0) AND deleted=0 ORDER BY idsegment DESC LIMIT 1" 2>/dev/null
    fi
}

format_segment_json() {
    local data="$1"
    local seg_name="$2"
    if [ -z "$data" ]; then
        echo "{\"found\": false, \"name\": \"$(escape_json "$seg_name")\"}"
        return
    fi
    local id=$(echo "$data" | cut -f1)
    local name=$(escape_json "$(echo "$data" | cut -f2)")
    local definition=$(escape_json "$(echo "$data" | cut -f3)")
    local enable_all=$(echo "$data" | cut -f4 | tr -d '[:space:]')
    local idsite=$(echo "$data" | cut -f5 | tr -d '[:space:]')
    echo "{\"found\": true, \"idsegment\": \"$id\", \"name\": \"$name\", \"definition\": \"$definition\", \"enable_all_users\": \"$enable_all\", \"enable_only_idsite\": \"$idsite\"}"
}

S1=$(query_segment "$SITE_ID" "Returning Customers")
S2=$(query_segment "$SITE_ID" "Mobile Shoppers")

S1_JSON=$(format_segment_json "$S1" "Returning Customers")
S2_JSON=$(format_segment_json "$S2" "Mobile Shoppers")

CURRENT_SEGMENT_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_segment WHERE (enable_only_idsite=$SITE_ID OR enable_only_idsite=0) AND deleted=0" 2>/dev/null || echo "0")
echo "Segments exported."

# ── Query dashboard ───────────────────────────────────────────────────────
DASHBOARD_LAYOUT=$(matomo_query "SELECT layout FROM matomo_user_dashboard WHERE name='Weekly Performance' AND login='admin' LIMIT 1" 2>/dev/null || echo "")
DASHBOARD_EXISTS="false"
if [ -n "$DASHBOARD_LAYOUT" ]; then
    DASHBOARD_EXISTS="true"
fi
echo "Dashboard exported."

# ── Query custom dimensions ───────────────────────────────────────────────
query_dim() {
    local site_id="$1"
    local dim_name="$2"
    if [ -n "$site_id" ]; then
        matomo_query "SELECT idcustomdimension, name, scope, active FROM matomo_custom_dimensions WHERE LOWER(TRIM(name))=LOWER('$dim_name') AND idsite=$site_id LIMIT 1" 2>/dev/null
    fi
}

format_dim_json() {
    local data="$1"
    local dim_name="$2"
    if [ -z "$data" ]; then
        echo "{\"found\": false, \"name\": \"$(escape_json "$dim_name")\"}"
        return
    fi
    local id=$(echo "$data" | cut -f1)
    local name=$(escape_json "$(echo "$data" | cut -f2)")
    local scope=$(echo "$data" | cut -f3 | tr -d '[:space:]')
    local active=$(echo "$data" | cut -f4 | tr -d '[:space:]')
    echo "{\"found\": true, \"idcustomdimension\": \"$id\", \"name\": \"$name\", \"scope\": \"$scope\", \"active\": \"$active\"}"
}

DIM1=$(query_dim "$SITE_ID" "Customer Tier")
DIM1_JSON=$(format_dim_json "$DIM1" "Customer Tier")

CURRENT_DIM_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_custom_dimensions WHERE idsite=$SITE_ID" 2>/dev/null || echo "0")
echo "Custom dimensions exported."

# ── Current goal IDs (for anti-gaming: detect delete-and-recreate) ────────
CURRENT_GOAL_IDS=$(matomo_query "SELECT idgoal FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0 ORDER BY idgoal" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# ── Write result JSON ─────────────────────────────────────────────────────
# Write dashboard layout to temp file (avoids quote-escaping issues in Python)
echo "$DASHBOARD_LAYOUT" > /tmp/_dashboard_layout.txt

# Write Python script to temp file to avoid bash quoting issues with JSON
cat > /tmp/_build_result.py << 'PYEOF'
import json, sys

task_start = int(sys.argv[1])
task_end = int(sys.argv[2])
site_id = sys.argv[3]
initial_seg_count = int(sys.argv[4])
current_seg_count = int(sys.argv[5])
initial_dim_count = int(sys.argv[6])
current_dim_count = int(sys.argv[7])
initial_goal_ids = sys.argv[8]
current_goal_ids = sys.argv[9]
export_ts = sys.argv[10]

# Read dashboard layout from file
with open('/tmp/_dashboard_layout.txt', 'r') as f:
    dashboard_layout_raw = f.read().strip()
dashboard_layout_parsed = None
try:
    dashboard_layout_parsed = json.loads(dashboard_layout_raw)
except:
    pass

# Read sub-JSONs from files
def read_json_file(path):
    try:
        with open(path) as f:
            return json.loads(f.read())
    except:
        return {"found": False}

goals = {
    "product_page_view": read_json_file('/tmp/_g1.json'),
    "add_to_cart": read_json_file('/tmp/_g2.json'),
    "begin_checkout": read_json_file('/tmp/_g3.json'),
    "purchase_complete": read_json_file('/tmp/_g4.json'),
}
segments = {
    "returning_customers": read_json_file('/tmp/_s1.json'),
    "mobile_shoppers": read_json_file('/tmp/_s2.json'),
}
custom_dims = {
    "customer_tier": read_json_file('/tmp/_dim1.json'),
}

result = {
    "task_start_timestamp": task_start,
    "task_end_timestamp": task_end,
    "site_id": site_id,
    "goals": goals,
    "segments": segments,
    "initial_segment_count": initial_seg_count,
    "current_segment_count": current_seg_count,
    "dashboard": {
        "exists": dashboard_layout_parsed is not None,
        "layout_raw": dashboard_layout_raw,
        "layout_parsed": dashboard_layout_parsed,
    },
    "custom_dimensions": custom_dims,
    "initial_dimension_count": initial_dim_count,
    "current_dimension_count": current_dim_count,
    "initial_goal_ids": initial_goal_ids.strip(),
    "current_goal_ids": current_goal_ids.strip(),
    "export_timestamp": export_ts,
}

print(json.dumps(result, indent=2))
PYEOF

# Write sub-JSON fragments to temp files
echo "$G1_JSON" > /tmp/_g1.json
echo "$G2_JSON" > /tmp/_g2.json
echo "$G3_JSON" > /tmp/_g3.json
echo "$G4_JSON" > /tmp/_g4.json
echo "$S1_JSON" > /tmp/_s1.json
echo "$S2_JSON" > /tmp/_s2.json
echo "$DIM1_JSON" > /tmp/_dim1.json

python3 /tmp/_build_result.py \
    "$TASK_START" "$TASK_END" "$SITE_ID" \
    "${INITIAL_SEGMENT_COUNT:-0}" "${CURRENT_SEGMENT_COUNT:-0}" \
    "${INITIAL_DIM_COUNT:-0}" "${CURRENT_DIM_COUNT:-0}" \
    "$INITIAL_GOAL_IDS" "$CURRENT_GOAL_IDS" \
    "$(date -Iseconds)" \
    > /tmp/remediate_analytics_audit_result.json 2>/dev/null

if [ ! -s /tmp/remediate_analytics_audit_result.json ]; then
    echo "WARNING: Python JSON construction failed"
fi

# Cleanup temp files
rm -f /tmp/_build_result.py /tmp/_dashboard_layout.txt /tmp/_g[1-4].json /tmp/_s[1-2].json /tmp/_dim1.json 2>/dev/null

rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/remediate_analytics_audit_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "Result JSON saved to /tmp/remediate_analytics_audit_result.json"
cat /tmp/remediate_analytics_audit_result.json
echo ""
echo "=== Export Complete ==="
