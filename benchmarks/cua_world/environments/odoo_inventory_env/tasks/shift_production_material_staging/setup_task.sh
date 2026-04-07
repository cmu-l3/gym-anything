#!/bin/bash
# Setup script for shift_production_material_staging task

source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"

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

date +%s > /tmp/task_start_timestamp
rm -f /tmp/staging_result.json 2>/dev/null || true

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Always drop and recreate for a clean, deterministic state
    echo "Dropping and recreating database '${ODOO_DB}'..."
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
    sleep 2
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
    sleep 2

    # Verify the DB was created
    DB_CREATED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    
    if [ "$DB_CREATED" = "1" ]; then
        echo "Initializing Odoo modules (this will take 3-5 minutes)..."
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
            -i base,stock,sale_management,purchase \
            --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true

        # Set admin credentials
        docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
            -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
    else
        echo "ERROR: Could not create database."
    fi

    echo "Restarting Odoo web server..."
    docker restart odoo-web 2>/dev/null || true

    echo "Waiting for Odoo web..."
    for _j in $(seq 1 90); do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && break
        sleep 5
    done

    # Wait for module registry to load
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
    echo "Database initialized. Auth: ${AUTH_OK}"

    # Use python XML-RPC to setup the exact staging scenario
    echo "Configuring Material Staging Scenario..."
    python3 << PYEOF
import xmlrpc.client, time, sys

url = 'http://localhost:8069'
db = '${ODOO_DB}'
password = 'admin'
common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)

uid = None
for _ in range(10):
    try:
        uid = common.authenticate(db, 'admin', password, {})
        if uid: break
    except:
        time.sleep(2)

if not uid:
    print("Failed to authenticate.")
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)
def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

# 1. Setup locations
wh = execute('stock.warehouse', 'search_read', [], ['lot_stock_id'], limit=1)[0]
stock_loc_id = wh['lot_stock_id'][0]

def get_or_create_loc(name, parent_id):
    existing = execute('stock.location', 'search_read', [[['name', '=', name], ['location_id', '=', parent_id]]], ['id'])
    if existing: return existing[0]['id']
    return execute('stock.location', 'create', [{'name': name, 'location_id': parent_id, 'usage': 'internal'}])

bulk_id = get_or_create_loc('Bulk Silos', stock_loc_id)
over_id = get_or_create_loc('Overflow', stock_loc_id)
add_id = get_or_create_loc('Additives Room', stock_loc_id)
ext_id = get_or_create_loc('Extruder Line 3', stock_loc_id)

# 2. Setup products
def get_or_create_prod(name, code):
    existing = execute('product.product', 'search_read', [[['default_code', '=', code]]], ['id'])
    if existing: return existing[0]['id']
    return execute('product.product', 'create', [{'name': name, 'type': 'product', 'default_code': code}])

prod_pp = get_or_create_prod('PP-Resin-01 (Polypropylene)', 'PP-Resin-01')
prod_hdpe = get_or_create_prod('HDPE-Resin-02 (High-Density Polyethylene)', 'HDPE-Resin-02')
prod_mb = get_or_create_prod('MB-Blue-05 (Blue Masterbatch)', 'MB-Blue-05')
prod_uv = get_or_create_prod('UV-Stab-09 (UV Stabilizer)', 'UV-Stab-09')

# 3. Setup Vendor
def get_or_create_vendor(name):
    existing = execute('res.partner', 'search_read', [[['name', '=', name]]], ['id'])
    if existing: return existing[0]['id']
    return execute('res.partner', 'create', [{'name': name, 'supplier_rank': 1, 'is_company': True}])

vendor_id = get_or_create_vendor('PolyChem Additives')

# 4. Set Inventory
def set_stock(prod_id, loc_id, qty):
    quants = execute('stock.quant', 'search_read', [[['product_id', '=', prod_id], ['location_id', '=', loc_id]]], ['id', 'quantity'])
    if quants:
        if abs(quants[0]['quantity'] - qty) < 0.1:
            return
        quant_id = quants[0]['id']
        execute('stock.quant', 'write', [[quant_id], {'inventory_quantity': qty}])
    else:
        quant_id = execute('stock.quant', 'create', [{'product_id': prod_id, 'location_id': loc_id, 'inventory_quantity': qty}])
    execute('stock.quant', 'action_apply_inventory', [[quant_id]])

set_stock(prod_pp, bulk_id, 10000)
set_stock(prod_hdpe, bulk_id, 2000)
set_stock(prod_hdpe, over_id, 5000)
set_stock(prod_mb, add_id, 200)
set_stock(prod_uv, stock_loc_id, 0) # Guarantee 0

print("Material Staging Scenario configured successfully.")
PYEOF
fi

# Ensure Firefox is running and focused
OPENEMR_URL="http://localhost:8069/web/login"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Try to focus and maximize window
if wait_for_window "firefox\|mozilla\|Odoo" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial screenshot for VLM / proof
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task Setup Complete ==="