#!/bin/bash
# Setup script for Supply Chain Lead Times Task

source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"

# Detect PostgreSQL container
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
date +%s > /tmp/task_start_time.txt
rm -f /tmp/supply_chain_lead_times_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Check DB Usability
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    if [ "$DB_USABLE" != "1" ]; then
        echo "Database '${ODOO_DB}' not usable. Recreating..."
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
        sleep 2
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        sleep 2
        
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" -i base,stock,sale_management,purchase --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true
        docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        docker restart odoo-web 2>/dev/null || true
        sleep 10
    fi
    
    # Wait for Odoo to be fully accessible
    for _j in $(seq 1 30); do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${ODOO_URL}/web/login" 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && break
        sleep 2
    done

    # Run Python script via XML-RPC to seed the vendor, products, and reset lead times
    echo "Seeding initial data and resetting lead times..."
    python3 << 'PYEOF'
import xmlrpc.client
import time
import sys

url = 'http://localhost:8069'
db = 'odoo_inventory'
user = 'admin'
password = 'admin'

common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url), allow_none=True)
uid = None
for i in range(30):
    try:
        uid = common.authenticate(db, user, password, {})
        if uid: break
    except Exception:
        pass
    time.sleep(2)

if not uid:
    print("FATAL: Could not authenticate with Odoo XML-RPC")
    sys.exit(1)

models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url), allow_none=True)
def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

# 1. Ensure Company Security Lead Times are disabled/0
company_ids = execute('res.company', 'search', [[]])
if company_ids:
    execute('res.company', 'write', [company_ids, {'security_lead': 0.0, 'po_lead': 0.0}])

# 2. Create Vendor
vendor_ids = execute('res.partner', 'search', [[('name', '=', 'GlobalTech Industries')]])
if not vendor_ids:
    execute('res.partner', 'create', [{'name': 'GlobalTech Industries', 'is_company': True}])

# 3. Create Products and reset their lead times
products = [
    {'name': 'STM32F401 Microcontroller', 'default_code': 'COMP-MCU-STM32', 'type': 'product'},
    {'name': 'ESP32-WROOM-32 WiFi Module', 'default_code': 'COMP-WIFI-ESP32', 'type': 'product'},
    {'name': 'Raspberry Pi Compute Module 4', 'default_code': 'COMP-SBC-RPI4', 'type': 'product'}
]

for p in products:
    p_ids = execute('product.template', 'search', [[('default_code', '=', p['default_code'])]])
    if not p_ids:
        tmpl_id = execute('product.template', 'create', [{
            'name': p['name'],
            'default_code': p['default_code'],
            'type': p['type'],
            'sale_delay': 0.0
        }])
    else:
        tmpl_id = p_ids[0]
        execute('product.template', 'write', [[tmpl_id], {'sale_delay': 0.0}])
        # Delete existing supplier info to ensure clean slate
        sup_ids = execute('product.supplierinfo', 'search', [[('product_tmpl_id', '=', tmpl_id)]])
        if sup_ids:
            execute('product.supplierinfo', 'unlink', [sup_ids])

print("Data seeded successfully via XML-RPC")
PYEOF

    # Start and maximize Firefox
    if ! pgrep -f firefox > /dev/null; then
        echo "Starting Firefox..."
        su - ga -c "DISPLAY=:1 firefox '${ODOO_URL}/web/login' > /tmp/firefox_task.log 2>&1 &"
        sleep 5
    fi

    WID=$(DISPLAY=:1 wmctrl -l | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

sleep 2
take_screenshot "/tmp/task_initial_state.png" || true

echo "=== Task Setup Complete ==="