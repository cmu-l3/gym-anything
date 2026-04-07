#!/bin/bash

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

date +%s > /tmp/scrap_task_start_timestamp
rm -f /tmp/scrap_task_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Check database usability
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    
    if [ "$DB_USABLE" != "1" ]; then
        echo "Database '${ODOO_DB}' not usable. Dropping and recreating..."
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
        sleep 2
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        sleep 2

        DB_CREATED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
        
        if [ "$DB_CREATED" = "1" ]; then
            echo "Initializing Odoo modules (this may take 3-5 minutes)..."
            docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
                -i base,stock \
                --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true

            docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
                -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        fi
        
        docker restart odoo-web 2>/dev/null || true
        
        echo "Waiting for Odoo web..."
        for _j in $(seq 1 90); do
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
    else
        echo "Database '${ODOO_DB}' is usable."
    fi

    # Wipe existing scrap orders for clean state
    docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -c "DELETE FROM stock_scrap;" 2>/dev/null || true

    echo "Seeding spare parts data..."
    python3 << PYEOF
import xmlrpc.client

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

wh = execute('stock.warehouse', 'search_read', [[]], fields=['lot_stock_id'], limit=1)
if not wh:
    print("Warehouse not found!")
    exit(1)
stock_loc_id = wh[0]['lot_stock_id'][0]

products_data = [
    ('SCRAP-001', 'Timken 6205-2RS Deep Groove Ball Bearing', 40),
    ('SCRAP-002', 'Gates PowerGrip GT3 8MGT-1280 Timing Belt', 20),
    ('SCRAP-003', 'Parker 421SN-8 Hydraulic Hose Assembly', 12),
    ('SCRAP-004', 'SKF 22215 E Spherical Roller Bearing', 30),
    ('SCRAP-005', 'Bando 5VX800 Power Ace V-Belt', 25),
    ('SCRAP-006', 'Festo DNC-40-100-PPV-A Pneumatic Cylinder', 10),
]

for code, name, qty in products_data:
    tmpl_ids = execute('product.template', 'search', [[['default_code', '=', code]]])
    if tmpl_ids:
        tmpl_id = tmpl_ids[0]
    else:
        tmpl_id = execute('product.template', 'create', [{
            'name': name,
            'type': 'product',
            'default_code': code,
            'list_price': 50.0,
            'standard_price': 25.0
        }])
        
    tmpl = execute('product.template', 'read', [[tmpl_id]], fields=['product_variant_ids'])
    prod_id = tmpl[0]['product_variant_ids'][0]
    
    # Check and set quantity
    quants = execute('stock.quant', 'search', [[['product_id', '=', prod_id], ['location_id', '=', stock_loc_id]]])
    if quants:
        execute('stock.quant', 'write', [quants, {'inventory_quantity': qty}])
        execute('stock.quant', 'action_apply_inventory', [quants])
    else:
        quant_id = execute('stock.quant', 'create', [{
            'product_id': prod_id,
            'location_id': stock_loc_id,
            'inventory_quantity': qty
        }])
        execute('stock.quant', 'action_apply_inventory', [[quant_id]])

print("Products seeded and stock adjusted successfully.")
PYEOF

    echo "Initial state configured."
fi

# Launch Firefox
echo "Starting Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Focus & Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/scrap_initial_state.png

echo "=== Task Setup Complete ==="