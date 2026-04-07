#!/bin/bash
# Note: no set -euo pipefail — commands need to be fault-tolerant

source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"
ODOO_USER="admin"
ODOO_PASS="admin"

# Detect actual PostgreSQL container name
PG_CONTAINER=""
for name in odoo-db odoo-postgres; do
    if docker exec "$name" pg_isready -U odoo 2>/dev/null; then
        PG_CONTAINER="$name"
        break
    fi
done

if [ -z "$PG_CONTAINER" ]; then
    echo "ERROR: No PostgreSQL container found. Trying docker-compose..."
    cd /home/ga/odoo
    docker-compose up -d 2>/dev/null || true
    sleep 10
    for name in odoo-db odoo-postgres; do
        if docker exec "$name" pg_isready -U odoo 2>/dev/null; then
            PG_CONTAINER="$name"
            break
        fi
    done
fi
echo "PostgreSQL container: ${PG_CONTAINER:-NOT FOUND}"

# Timestamp for anti-gaming
date +%s > /tmp/configure_multistep_task_start_timestamp
rm -f /tmp/configure_multistep_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Check if DB is usable
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    if [ "$DB_USABLE" != "1" ]; then
        echo "Database '${ODOO_DB}' not usable. Recreating..."
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
        sleep 2
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        sleep 2

        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
            -i base,stock,sale_management,purchase \
            --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true
            
        docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
            -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
            
        docker restart odoo-web 2>/dev/null || true
    fi

    echo "Waiting for Odoo web..."
    for _j in $(seq 1 60); do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && break
        sleep 5
    done
    
    echo "Waiting for module registry..."
    for _k in $(seq 1 30); do
        AUTH_OK=$(python3 -c "
import xmlrpc.client
try:
    c = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = c.authenticate('${ODOO_DB}', 'admin', 'admin', {})
    print('OK' if uid else 'FAIL')
except:
    print('FAIL')
" 2>/dev/null)
        [ "$AUTH_OK" = "OK" ] && break
        sleep 5
    done

    # Reset warehouse configuration to 1-step and disable multi-step routes
    echo "Resetting warehouse configuration..."
    python3 << PYEOF
import xmlrpc.client, json
url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)
    
    whs = models.execute_kw(db, uid, password, 'stock.warehouse', 'search', [[['code', '=', 'WH']]])
    if whs:
        models.execute_kw(db, uid, password, 'stock.warehouse', 'write', [whs, {'reception_steps': 'one_step', 'delivery_steps': 'ship_only'}])
        
    wh_data = models.execute_kw(db, uid, password, 'stock.warehouse', 'read', [whs], {'fields': ['reception_steps', 'delivery_steps']})
    with open('/tmp/initial_warehouse_state.json', 'w') as f:
        json.dump(wh_data[0] if wh_data else {}, f)
        
    # Attempt to disable the group_stock_adv_location setting
    groups = models.execute_kw(db, uid, password, 'res.groups', 'search', [[['category_id.name', 'ilike', 'Inventory'], ['name', 'ilike', 'Multi-Step']]])
    if groups:
        models.execute_kw(db, uid, password, 'res.groups', 'write', [groups, {'users': [(5, 0, 0)]}])
        
except Exception as e:
    print("Error setting up Odoo state:", e)
PYEOF
fi

# Ensure Firefox is running and focused on Odoo
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|Odoo" 15 || true

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="