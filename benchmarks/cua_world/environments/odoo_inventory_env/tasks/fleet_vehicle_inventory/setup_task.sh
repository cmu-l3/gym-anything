#!/bin/bash

source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"
ODOO_USER="admin"
ODOO_PASS="admin"

echo "=== Setting up Fleet Vehicle Inventory Task ==="
date +%s > /tmp/fleet_vehicle_task_start_timestamp

# Ensure Odoo is running
PG_CONTAINER=""
for name in odoo-db odoo-postgres; do
    if docker exec "$name" pg_isready -U odoo 2>/dev/null; then
        PG_CONTAINER="$name"
        break
    fi
done

if [ -z "$PG_CONTAINER" ]; then
    echo "Starting Odoo containers..."
    cd /home/ga/odoo && docker-compose up -d 2>/dev/null || true
    sleep 10
    for name in odoo-db odoo-postgres; do
        if docker exec "$name" pg_isready -U odoo 2>/dev/null; then
            PG_CONTAINER="$name"
            break
        fi
    done
fi

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: PostgreSQL container not found."
    exit 1
fi

# Ensure basic modules are installed (quick check/init)
DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
if [ "$DB_USABLE" != "1" ]; then
    echo "Initializing fresh database..."
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
    sleep 2
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
    docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" -i base,stock,sale_management,purchase --stop-after-init 2>&1 | tail -20 || true
    docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
    docker restart odoo-web
fi

# Wait for Odoo API
echo "Waiting for Odoo API..."
for _j in $(seq 1 30); do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
    if [ "$HTTP" = "200" ]; then
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
    fi
    sleep 3
done

echo "Setting up initial fleet inventory data..."

python3 << 'PYEOF'
import xmlrpc.client, sys

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    if not uid:
        print("Auth failed")
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    # 1. Get WH/Stock
    stock_locs = execute('stock.location', 'search_read', [[('name', '=', 'Stock')]], {'limit': 1, 'fields': ['id']})
    if not stock_locs:
        print("WH/Stock not found!")
        sys.exit(1)
    wh_stock_id = stock_locs[0]['id']

    # 2. Setup Van A
    van_a_ids = execute('stock.location', 'search', [[('name', '=', 'Van A'), ('location_id', '=', wh_stock_id)]])
    if not van_a_ids:
        van_a_id = execute('stock.location', 'create', {'name': 'Van A', 'location_id': wh_stock_id, 'usage': 'internal'})
    else:
        van_a_id = van_a_ids[0]

    # 3. Setup Van B
    van_b_ids = execute('stock.location', 'search', [[('name', '=', 'Van B'), ('location_id', '=', wh_stock_id), '|', ('active','=',True), ('active','=',False)]])
    if not van_b_ids:
        van_b_id = execute('stock.location', 'create', {'name': 'Van B', 'location_id': wh_stock_id, 'usage': 'internal', 'active': True})
    else:
        van_b_id = van_b_ids[0]
        execute('stock.location', 'write', [[van_b_id], {'active': True}])

    # 4. Create Products
    products_data = [
        {'name': 'Honeywell TH6220U2000 Thermostat', 'type': 'product', 'default_code': 'HVAC-THM-01'},
        {'name': 'Titan 35/5 MFD Dual Capacitor', 'type': 'product', 'default_code': 'HVAC-CAP-01'},
        {'name': 'Supco SPP6 Hard Start Kit', 'type': 'product', 'default_code': 'HVAC-HSK-01'},
        {'name': 'Emerson 50VA Transformer', 'type': 'product', 'default_code': 'HVAC-TRF-01'},
        {'name': 'Fieldpiece SC260', 'type': 'product', 'default_code': 'HVAC-MTR-01'},
    ]

    p_ids = {}
    for pd in products_data:
        p_search = execute('product.product', 'search', [[('default_code', '=', pd['default_code'])]])
        if not p_search:
            p_id = execute('product.product', 'create', pd)
        else:
            p_id = p_search[0]
        p_ids[pd['default_code']] = p_id

    # 5. Populate WH/Stock
    for code, p_id in p_ids.items():
        q_search = execute('stock.quant', 'search', [[('product_id', '=', p_id), ('location_id', '=', wh_stock_id)]])
        if q_search:
            execute('stock.quant', 'write', [q_search, {'inventory_quantity': 100}])
            execute('stock.quant', 'action_apply_inventory', [q_search])
        else:
            q_id = execute('stock.quant', 'create', {'product_id': p_id, 'location_id': wh_stock_id, 'inventory_quantity': 100})
            execute('stock.quant', 'action_apply_inventory', [[q_id]])

    # 6. Empty Van A
    qa_search = execute('stock.quant', 'search', [[('location_id', '=', van_a_id)]])
    if qa_search:
        execute('stock.quant', 'write', [qa_search, {'inventory_quantity': 0}])
        execute('stock.quant', 'action_apply_inventory', [qa_search])

    # 7. Seed Van B with random stuff to be discovered
    van_b_seed = [
        (p_ids['HVAC-TRF-01'], 3),
        (p_ids['HVAC-MTR-01'], 2),
        (p_ids['HVAC-HSK-01'], 4),
    ]
    
    # clear existing van B first
    qb_clear = execute('stock.quant', 'search', [[('location_id', '=', van_b_id)]])
    if qb_clear:
        execute('stock.quant', 'write', [qb_clear, {'inventory_quantity': 0}])
        execute('stock.quant', 'action_apply_inventory', [qb_clear])

    for p_id, qty in van_b_seed:
        q_id = execute('stock.quant', 'create', {'product_id': p_id, 'location_id': van_b_id, 'inventory_quantity': qty})
        execute('stock.quant', 'action_apply_inventory', [[q_id]])

    print("Setup DB Success.")
except Exception as e:
    print(f"Setup Error: {e}")
PYEOF

# Open Firefox and take screenshot
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' &"
    sleep 5
fi

# Maximize and Focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/fleet_initial.png ga

echo "=== Setup Complete ==="