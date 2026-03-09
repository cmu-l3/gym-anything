#!/bin/bash
# Shared utilities for Odoo CRM tasks

ODOO_URL="http://localhost:8069"
ODOO_DB="odoodb"
ODOO_USER="admin"
ODOO_PASS="admin"
# CRM pipeline URL (hash-based, action=209 is stable for this Odoo installation)
CRM_PIPELINE_URL="http://localhost:8069/web#action=209&cids=1&menu_id=139"

# ===== Screenshot =====
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
    echo "Screenshot saved to $path"
}

# ===== Database query via Docker =====
odoo_db_query() {
    local query="$1"
    docker exec odoo-db psql -U odoo -d odoodb -t -A -c "$query" 2>/dev/null
}

# ===== XML-RPC query helper =====
odoo_rpc_call() {
    # $1 = model, $2 = method, $3 = JSON args (optional)
    local model="$1"
    local method="$2"
    local args="${3:-[]}"

    python3 - <<PYEOF
import xmlrpc.client
import sys
common = xmlrpc.client.ServerProxy('${ODOO_URL}/xmlrpc/2/common')
uid = common.authenticate('${ODOO_DB}', '${ODOO_USER}', '${ODOO_PASS}', {})
if not uid:
    print("AUTH_FAILED", file=sys.stderr)
    sys.exit(1)
models = xmlrpc.client.ServerProxy('${ODOO_URL}/xmlrpc/2/object')
result = models.execute_kw('${ODOO_DB}', uid, '${ODOO_PASS}', '${model}', '${method}', ${args})
print(result)
PYEOF
}

# ===== Wait for Odoo to be ready =====
wait_for_odoo() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${ODOO_URL}/web/login" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "Odoo ready (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: Odoo not ready after ${timeout}s"
    return 1
}

# ===== Firefox management =====
ensure_firefox_running() {
    if ! pgrep -f firefox > /dev/null 2>&1; then
        echo "Starting Firefox..."
        # Launch without -profile flag (snap Firefox uses auto-detected default profile)
        su - ga -c "DISPLAY=:1 firefox http://localhost:8069/web/login &"
        sleep 12
    else
        echo "Firefox already running"
    fi
}

navigate_to_url() {
    local url="$1"
    ensure_firefox_running
    # Focus Firefox window
    DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
    sleep 0.5
    # Use address bar
    DISPLAY=:1 xdotool key --clearmodifiers ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "$url"
    DISPLAY=:1 xdotool key Return
    sleep 4
}

# ===== Log in to Odoo if not already logged in =====
ensure_odoo_logged_in() {
    local target_url="${1:-${CRM_PIPELINE_URL}}"

    ensure_firefox_running

    # Navigate to login page
    navigate_to_url "${ODOO_URL}/web/login"
    sleep 4

    # Fill login form - verified coordinates for 1920x1080:
    # Email at (993, 422), Password at (993, 503), Login button at (993, 569)
    DISPLAY=:1 xdotool mousemove 993 422 click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.3

    DISPLAY=:1 xdotool mousemove 993 503 click 1 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.3

    DISPLAY=:1 xdotool mousemove 993 569 click 1 2>/dev/null || true
    sleep 6

    # Navigate to target URL
    if [ "$target_url" != "${ODOO_URL}/web/login" ]; then
        navigate_to_url "$target_url"
        sleep 4
    fi

    echo "Login complete, navigated to $target_url"
}

# ===== Get a CRM lead/opportunity ID by name =====
get_lead_id_by_name() {
    local lead_name="$1"
    python3 - <<PYEOF 2>/dev/null
import xmlrpc.client
common = xmlrpc.client.ServerProxy('${ODOO_URL}/xmlrpc/2/common')
uid = common.authenticate('${ODOO_DB}', '${ODOO_USER}', '${ODOO_PASS}', {})
models = xmlrpc.client.ServerProxy('${ODOO_URL}/xmlrpc/2/object')
ids = models.execute_kw('${ODOO_DB}', uid, '${ODOO_PASS}', 'crm.lead', 'search',
    [[['name', '=', '${lead_name}']]])
print(ids[0] if ids else '')
PYEOF
}

# ===== Navigate Firefox to a specific Odoo record =====
navigate_to_odoo_record() {
    local model="$1"
    local record_id="$2"
    # Use hash-based URLs (Odoo 17 Community hash routing)
    case "$model" in
        crm.lead)
            # CRM pipeline action=209, form view for specific record
            navigate_to_url "${ODOO_URL}/web#action=209&id=${record_id}&model=crm.lead&view_type=form&cids=1&menu_id=139"
            ;;
        res.partner)
            # Contacts action=154 (standard contacts list)
            navigate_to_url "${ODOO_URL}/web#action=154&id=${record_id}&model=res.partner&view_type=form&cids=1&menu_id=117"
            ;;
        *)
            navigate_to_url "${CRM_PIPELINE_URL}"
            ;;
    esac
}

# ===== Seed a specific lead/opportunity via XML-RPC =====
create_or_update_lead() {
    local lead_name="$1"
    local partner_name="$2"
    local lead_type="$3"  # 'lead' or 'opportunity'
    local expected_revenue="$4"
    local stage_sequence="${5:-1}"

    python3 - <<PYEOF 2>/dev/null
import xmlrpc.client

common = xmlrpc.client.ServerProxy('${ODOO_URL}/xmlrpc/2/common')
uid = common.authenticate('${ODOO_DB}', '${ODOO_USER}', '${ODOO_PASS}', {})
models = xmlrpc.client.ServerProxy('${ODOO_URL}/xmlrpc/2/object')

# Get stage
stages = models.execute_kw('${ODOO_DB}', uid, '${ODOO_PASS}', 'crm.stage', 'search_read',
    [[['sequence', '<=', ${stage_sequence}]]], {'fields': ['id', 'name', 'sequence'], 'order': 'sequence', 'limit': 1})
stage_id = stages[0]['id'] if stages else None

# Check if lead already exists
existing = models.execute_kw('${ODOO_DB}', uid, '${ODOO_PASS}', 'crm.lead', 'search',
    [[['name', '=', '${lead_name}']]])

data = {
    'name': '${lead_name}',
    'partner_name': '${partner_name}',
    'type': '${lead_type}',
    'expected_revenue': ${expected_revenue},
    'probability': 20 if '${lead_type}' == 'opportunity' else 0,
}
if stage_id:
    data['stage_id'] = stage_id

if existing:
    models.execute_kw('${ODOO_DB}', uid, '${ODOO_PASS}', 'crm.lead', 'write',
        [existing, data])
    print(f"Updated lead ID: {existing[0]}")
else:
    new_id = models.execute_kw('${ODOO_DB}', uid, '${ODOO_PASS}', 'crm.lead', 'create', [data])
    print(f"Created lead ID: {new_id}")
PYEOF
}
