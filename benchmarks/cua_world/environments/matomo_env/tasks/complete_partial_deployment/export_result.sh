#!/bin/bash
# Export script for Complete Partial Deployment task
# Queries site config, goals, custom dimensions, segments, Tag Manager,
# users, and dashboard, then packages into a JSON result file.

echo "=== Exporting Complete Partial Deployment Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SITE_ID=$(cat /tmp/cpd_site_id 2>/dev/null || echo "")
INITIAL_GOAL_IDS=$(cat /tmp/cpd_initial_goal_ids.txt 2>/dev/null || echo "")
INITIAL_GOAL_COUNT=$(cat /tmp/cpd_initial_goal_count.txt 2>/dev/null || echo "0")
INITIAL_SEG_COUNT=$(cat /tmp/cpd_initial_segment_count.txt 2>/dev/null || echo "0")
INITIAL_DIM_COUNT=$(cat /tmp/cpd_initial_dim_count.txt 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/cpd_initial_user_count.txt 2>/dev/null || echo "0")
INITIAL_TM_COUNT=$(cat /tmp/cpd_initial_tm_count.txt 2>/dev/null || echo "0")
INITIAL_SITE1=$(cat /tmp/cpd_initial_site1_state.txt 2>/dev/null || echo "")

echo "GlobalRetail Corp site ID: $SITE_ID"

# ── Debug dump ───────────────────────────────────────────────────────────
echo ""
echo "=== DEBUG: Site config ==="
matomo_query_verbose "SELECT idsite, name, currency, timezone, ecommerce, excluded_parameters FROM matomo_site WHERE idsite=$SITE_ID" 2>/dev/null
echo "=== DEBUG: Goals ==="
matomo_query_verbose "SELECT idgoal, name, pattern, pattern_type, match_attribute, deleted FROM matomo_goal WHERE idsite=$SITE_ID ORDER BY idgoal" 2>/dev/null
echo "=== DEBUG: Custom Dimensions ==="
matomo_query_verbose "SELECT idcustomdimension, name, scope, active FROM matomo_custom_dimensions WHERE idsite=$SITE_ID" 2>/dev/null
echo "=== DEBUG: Segments ==="
matomo_query_verbose "SELECT idsegment, name, definition, enable_all_users, enable_only_idsite, deleted FROM matomo_segment WHERE deleted=0 ORDER BY idsegment" 2>/dev/null
echo "=== DEBUG: Users ==="
matomo_query_verbose "SELECT login, email, superuser_access FROM matomo_user WHERE login NOT IN ('admin','anonymous')" 2>/dev/null
echo "=== DEBUG: Access ==="
matomo_query_verbose "SELECT login, access, idsite FROM matomo_access WHERE login NOT IN ('admin','anonymous')" 2>/dev/null
echo "=== DEBUG: Dashboards ==="
matomo_query_verbose "SELECT iddashboard, login, name, LEFT(layout, 200) AS layout_preview FROM matomo_user_dashboard WHERE login='admin' ORDER BY iddashboard" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# ── Helper ───────────────────────────────────────────────────────────────
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' '
}

# ── Query site config ────────────────────────────────────────────────────
SITE_CURRENCY=$(matomo_query "SELECT currency FROM matomo_site WHERE idsite=$SITE_ID" 2>/dev/null || echo "")
SITE_TIMEZONE=$(matomo_query "SELECT timezone FROM matomo_site WHERE idsite=$SITE_ID" 2>/dev/null || echo "")
SITE_ECOMMERCE=$(matomo_query "SELECT ecommerce FROM matomo_site WHERE idsite=$SITE_ID" 2>/dev/null || echo "0")
SITE_EXCLUDED_PARAMS=$(matomo_query "SELECT excluded_parameters FROM matomo_site WHERE idsite=$SITE_ID" 2>/dev/null || echo "")

cat > /tmp/_site_config.json << SEOF
{
  "currency": "$(escape_json "$SITE_CURRENCY")",
  "timezone": "$(escape_json "$SITE_TIMEZONE")",
  "ecommerce": "$(echo "$SITE_ECOMMERCE" | tr -d '[:space:]')",
  "excluded_parameters": "$(escape_json "$SITE_EXCLUDED_PARAMS")"
}
SEOF
echo "Site config exported."

# ── Query goals ──────────────────────────────────────────────────────────
query_goal() {
    local site_id="$1" goal_name="$2"
    [ -n "$site_id" ] && matomo_query "SELECT idgoal, name, match_attribute, pattern, pattern_type FROM matomo_goal WHERE LOWER(TRIM(name))=LOWER('$goal_name') AND idsite=$site_id AND deleted=0 ORDER BY idgoal DESC LIMIT 1" 2>/dev/null
}

format_goal_json() {
    local data="$1" goal_name="$2"
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
G3=$(query_goal "$SITE_ID" "Checkout Started")
G4=$(query_goal "$SITE_ID" "Purchase Complete")

format_goal_json "$G1" "Product Page View" > /tmp/_g1.json
format_goal_json "$G2" "Add to Cart" > /tmp/_g2.json
format_goal_json "$G3" "Checkout Started" > /tmp/_g3.json
format_goal_json "$G4" "Purchase Complete" > /tmp/_g4.json

CURRENT_GOAL_IDS=$(matomo_query "SELECT idgoal FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0 ORDER BY idgoal" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
CURRENT_GOAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0" 2>/dev/null || echo "0")
echo "Goals exported."

# ── Query custom dimensions ──────────────────────────────────────────────
query_dim() {
    local site_id="$1" dim_name="$2"
    [ -n "$site_id" ] && matomo_query "SELECT idcustomdimension, name, scope, active FROM matomo_custom_dimensions WHERE LOWER(TRIM(name))=LOWER('$dim_name') AND idsite=$site_id LIMIT 1" 2>/dev/null
}

format_dim_json() {
    local data="$1" dim_name="$2"
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
DIM2=$(query_dim "$SITE_ID" "Page Category")

format_dim_json "$DIM1" "Customer Tier" > /tmp/_dim1.json
format_dim_json "$DIM2" "Page Category" > /tmp/_dim2.json

CURRENT_DIM_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_custom_dimensions WHERE idsite=$SITE_ID" 2>/dev/null || echo "0")
echo "Custom dimensions exported."

# ── Query segments ───────────────────────────────────────────────────────
query_segment() {
    local seg_name="$1"
    matomo_query "SELECT idsegment, name, definition, enable_all_users, enable_only_idsite FROM matomo_segment WHERE LOWER(TRIM(name))=LOWER('$seg_name') AND deleted=0 ORDER BY idsegment DESC LIMIT 1" 2>/dev/null
}

format_segment_json() {
    local data="$1" seg_name="$2"
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

S1=$(query_segment "High-Value Customers")
S2=$(query_segment "Mobile Shoppers")

format_segment_json "$S1" "High-Value Customers" > /tmp/_s1.json
format_segment_json "$S2" "Mobile Shoppers" > /tmp/_s2.json

CURRENT_SEG_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_segment WHERE deleted=0" 2>/dev/null || echo "0")
echo "Segments exported."

# ── Query Tag Manager ────────────────────────────────────────────────────
echo "Exporting Tag Manager data..."

# Use TSV export + Python conversion (works reliably on MariaDB 10.11)
docker exec matomo-db mysql -u matomo -pmatomo123 matomo -B -e \
    "SELECT idcontainer, name, created_date FROM matomo_tagmanager_container WHERE idsite=$SITE_ID AND deleted_date IS NULL" \
    > /tmp/_tm_containers.tsv 2>/dev/null || echo -e "idcontainer\tname\tcreated_date" > /tmp/_tm_containers.tsv

docker exec matomo-db mysql -u matomo -pmatomo123 matomo -B -e \
    "SELECT idtag, name, type, parameters, fire_trigger_ids FROM matomo_tagmanager_tag WHERE idsite=$SITE_ID AND deleted_date IS NULL" \
    > /tmp/_tm_tags.tsv 2>/dev/null || echo -e "idtag\tname\ttype\tparameters\tfire_trigger_ids" > /tmp/_tm_tags.tsv

docker exec matomo-db mysql -u matomo -pmatomo123 matomo -B -e \
    "SELECT idtrigger, name, type FROM matomo_tagmanager_trigger WHERE idsite=$SITE_ID AND deleted_date IS NULL" \
    > /tmp/_tm_triggers.tsv 2>/dev/null || echo -e "idtrigger\tname\ttype" > /tmp/_tm_triggers.tsv

docker exec matomo-db mysql -u matomo -pmatomo123 matomo -B -e \
    "SELECT idcontainerversion, name, status FROM matomo_tagmanager_container_version WHERE idsite=$SITE_ID AND deleted_date IS NULL" \
    > /tmp/_tm_versions.tsv 2>/dev/null || echo -e "idcontainerversion\tname\tstatus" > /tmp/_tm_versions.tsv

python3 -c "
import json, csv, sys

data = {'containers': [], 'tags': [], 'triggers': [], 'versions': []}

def read_tsv(fname):
    rows = []
    try:
        with open(fname, 'r') as f:
            reader = csv.DictReader(f, delimiter='\t')
            rows = list(reader)
    except: pass
    return rows

data['containers'] = read_tsv('/tmp/_tm_containers.tsv')
data['tags'] = read_tsv('/tmp/_tm_tags.tsv')
data['triggers'] = read_tsv('/tmp/_tm_triggers.tsv')
data['versions'] = read_tsv('/tmp/_tm_versions.tsv')

print(json.dumps(data))
" > /tmp/_tm_data.json 2>/dev/null || echo '{"containers":[],"tags":[],"triggers":[],"versions":[]}' > /tmp/_tm_data.json

echo "Tag Manager data exported."

# ── Query users ──────────────────────────────────────────────────────────
query_user() {
    local login="$1"
    matomo_query "SELECT login, email, superuser_access FROM matomo_user WHERE login='$login'" 2>/dev/null
}

query_user_access() {
    local login="$1"
    matomo_query "SELECT access, idsite FROM matomo_access WHERE login='$login' AND idsite=$SITE_ID" 2>/dev/null
}

format_user_json() {
    local user_data="$1" access_data="$2" login="$3"
    if [ -z "$user_data" ]; then
        echo "{\"found\": false, \"login\": \"$login\"}"
        return
    fi
    local ulogin=$(echo "$user_data" | cut -f1)
    local email=$(escape_json "$(echo "$user_data" | cut -f2)")
    local superuser=$(echo "$user_data" | cut -f3 | tr -d '[:space:]')
    local access="none"
    local access_site=""
    if [ -n "$access_data" ]; then
        access=$(echo "$access_data" | cut -f1 | tr -d '[:space:]')
        access_site=$(echo "$access_data" | cut -f2 | tr -d '[:space:]')
    fi
    echo "{\"found\": true, \"login\": \"$ulogin\", \"email\": \"$email\", \"superuser_access\": \"$superuser\", \"access\": \"$access\", \"access_site\": \"$access_site\"}"
}

U1_DATA=$(query_user "marketing_lead")
U1_ACCESS=$(query_user_access "marketing_lead")
U2_DATA=$(query_user "data_analyst")
U2_ACCESS=$(query_user_access "data_analyst")

format_user_json "$U1_DATA" "$U1_ACCESS" "marketing_lead" > /tmp/_u1.json
format_user_json "$U2_DATA" "$U2_ACCESS" "data_analyst" > /tmp/_u2.json

CURRENT_USER_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_user WHERE login NOT IN ('admin','anonymous')" 2>/dev/null || echo "0")
echo "Users exported."

# ── Query dashboard ──────────────────────────────────────────────────────
DASHBOARD_NAME=""
DASHBOARD_LAYOUT=""
DASHBOARD_EXISTS="false"

# Check for dashboard by expected name first, then any dashboard
DASHBOARD_DATA=$(matomo_query "SELECT name, layout FROM matomo_user_dashboard WHERE LOWER(name)=LOWER('Client Overview') AND login='admin' LIMIT 1" 2>/dev/null)
if [ -z "$DASHBOARD_DATA" ]; then
    # Fall back to newest non-default dashboard
    DASHBOARD_DATA=$(matomo_query "SELECT name, layout FROM matomo_user_dashboard WHERE login='admin' AND iddashboard > 1 ORDER BY iddashboard DESC LIMIT 1" 2>/dev/null)
fi

if [ -n "$DASHBOARD_DATA" ]; then
    DASHBOARD_EXISTS="true"
    DASHBOARD_NAME=$(echo "$DASHBOARD_DATA" | cut -f1)
    DASHBOARD_LAYOUT=$(echo "$DASHBOARD_DATA" | cut -f2-)
fi

echo "$DASHBOARD_LAYOUT" > /tmp/_dashboard_layout.txt
echo "Dashboard exported (exists=$DASHBOARD_EXISTS, name=$DASHBOARD_NAME)."

# ── Query Initial Site state (for anti-gaming) ───────────────────────────
SITE1_CURRENCY=$(matomo_query "SELECT currency FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "")
SITE1_TIMEZONE=$(matomo_query "SELECT timezone FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "")
SITE1_ECOMMERCE=$(matomo_query "SELECT ecommerce FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "")
echo "${SITE1_CURRENCY}|${SITE1_TIMEZONE}|${SITE1_ECOMMERCE}" > /tmp/_site1_current.txt
echo "Initial Site anti-gaming state captured."

# ── Build result JSON using Python ───────────────────────────────────────
cat > /tmp/_build_cpd_result.py << 'PYEOF'
import json, sys

task_start = int(sys.argv[1])
task_end = int(sys.argv[2])
site_id = sys.argv[3]
initial_goal_ids = sys.argv[4]
current_goal_ids = sys.argv[5]
initial_goal_count = int(sys.argv[6])
current_goal_count = int(sys.argv[7])
initial_seg_count = int(sys.argv[8])
current_seg_count = int(sys.argv[9])
initial_dim_count = int(sys.argv[10])
current_dim_count = int(sys.argv[11])
initial_user_count = int(sys.argv[12])
current_user_count = int(sys.argv[13])
initial_tm_count = int(sys.argv[14])
dashboard_exists = sys.argv[15].lower() == "true"
dashboard_name = sys.argv[16]
initial_site1_state = sys.argv[17]
current_site1_state = sys.argv[18]

def read_json_file(path):
    try:
        with open(path) as f:
            return json.loads(f.read())
    except:
        return {"found": False}

# Read dashboard layout
dashboard_layout_parsed = None
try:
    with open('/tmp/_dashboard_layout.txt', 'r') as f:
        raw = f.read().strip()
    dashboard_layout_parsed = json.loads(raw)
except:
    pass

result = {
    "task_start_timestamp": task_start,
    "task_end_timestamp": task_end,
    "site_id": site_id,
    "site_config": read_json_file('/tmp/_site_config.json'),
    "goals": {
        "product_page_view": read_json_file('/tmp/_g1.json'),
        "add_to_cart": read_json_file('/tmp/_g2.json'),
        "checkout_started": read_json_file('/tmp/_g3.json'),
        "purchase_complete": read_json_file('/tmp/_g4.json'),
    },
    "initial_goal_ids": initial_goal_ids.strip(),
    "current_goal_ids": current_goal_ids.strip(),
    "initial_goal_count": initial_goal_count,
    "current_goal_count": current_goal_count,
    "custom_dimensions": {
        "customer_tier": read_json_file('/tmp/_dim1.json'),
        "page_category": read_json_file('/tmp/_dim2.json'),
    },
    "initial_dimension_count": initial_dim_count,
    "current_dimension_count": current_dim_count,
    "segments": {
        "high_value_customers": read_json_file('/tmp/_s1.json'),
        "mobile_shoppers": read_json_file('/tmp/_s2.json'),
    },
    "initial_segment_count": initial_seg_count,
    "current_segment_count": current_seg_count,
    "tag_manager": read_json_file('/tmp/_tm_data.json'),
    "initial_tm_count": initial_tm_count,
    "users": {
        "marketing_lead": read_json_file('/tmp/_u1.json'),
        "data_analyst": read_json_file('/tmp/_u2.json'),
    },
    "initial_user_count": initial_user_count,
    "current_user_count": current_user_count,
    "dashboard": {
        "exists": dashboard_exists,
        "name": dashboard_name,
        "layout_raw": raw if dashboard_layout_parsed else "",
        "layout_parsed": dashboard_layout_parsed,
    },
    "antigaming": {
        "initial_site1_state": initial_site1_state,
        "current_site1_state": current_site1_state,
    },
    "export_timestamp": task_end,
}

print(json.dumps(result, indent=2))
PYEOF

python3 /tmp/_build_cpd_result.py \
    "$TASK_START" "$TASK_END" "$SITE_ID" \
    "$INITIAL_GOAL_IDS" "$CURRENT_GOAL_IDS" \
    "${INITIAL_GOAL_COUNT:-0}" "${CURRENT_GOAL_COUNT:-0}" \
    "${INITIAL_SEG_COUNT:-0}" "${CURRENT_SEG_COUNT:-0}" \
    "${INITIAL_DIM_COUNT:-0}" "${CURRENT_DIM_COUNT:-0}" \
    "${INITIAL_USER_COUNT:-0}" "${CURRENT_USER_COUNT:-0}" \
    "${INITIAL_TM_COUNT:-0}" \
    "$DASHBOARD_EXISTS" "$(escape_json "$DASHBOARD_NAME")" \
    "$INITIAL_SITE1" "$(cat /tmp/_site1_current.txt 2>/dev/null)" \
    > /tmp/complete_partial_deployment_result.json 2>/dev/null

if [ ! -s /tmp/complete_partial_deployment_result.json ]; then
    echo "WARNING: Python JSON construction failed, creating minimal result"
    echo '{"error": "JSON construction failed"}' > /tmp/complete_partial_deployment_result.json
fi

# Cleanup temp files
rm -f /tmp/_build_cpd_result.py /tmp/_site_config.json /tmp/_dashboard_layout.txt \
      /tmp/_g[1-4].json /tmp/_s[1-2].json /tmp/_dim[1-2].json /tmp/_u[1-2].json \
      /tmp/_tm_data.json /tmp/_tm_*.tsv /tmp/_site1_current.txt 2>/dev/null

rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/complete_partial_deployment_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "Result JSON saved to /tmp/complete_partial_deployment_result.json"
cat /tmp/complete_partial_deployment_result.json
echo ""
echo "=== Export Complete ==="
