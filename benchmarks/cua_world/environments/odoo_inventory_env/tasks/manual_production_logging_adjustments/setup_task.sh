#!/bin/bash
# Setup script for manual_production_logging_adjustments

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

if [ -n "$PG_CONTAINER" ]; then
    # Ensure database exists and modules are installed (standard check)
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    if [ "$DB_USABLE" != "1" ]; then
        echo "Database not usable. Dropping and recreating..."
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
        sleep 2
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        sleep 2
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" -i base,stock,sale_management,purchase --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true
        docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        docker restart odoo-web 2>/dev/null || true
        sleep 15
    fi

    # Initialize task data using Odoo's XML-RPC API
    echo "Setting up task-specific data (Products, Lots, Quants)..."
    python3 << 'PYEOF'
import xmlrpc.client
import time

url = 'http://localhost:8069'
db = 'odoo_inventory'
username = 'admin'
password = 'admin'

# Wait for Odoo to be fully ready
for _ in range(10):
    try:
        common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
        uid = common.authenticate(db, username, password, {})
        if uid:
            break
    except:
        time.sleep(2)

if not uid:
    print("Failed to authenticate to Odoo.")
    exit(1)

models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs or {})

# Get main stock location
wh = execute('stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
if not wh:
    print("No warehouse found.")
    exit(1)
stock_loc_id = wh[0]['lot_stock_id'][0]

# Helper to create product with lot tracking
def create_product(name):
    # Check if exists
    existing = execute('product.template', 'search_read', [[['name', '=', name]]], {'fields': ['id', 'product_variant_ids']})
    if existing:
        execute('product.template', 'write', [[existing[0]['id']], {'detailed_type': 'product', 'tracking': 'lot'}])
        return existing[0]['product_variant_ids'][0]
    
    tmpl_id = execute('product.template', 'create', [{
        'name': name,
        'detailed_type': 'product',
        'tracking': 'lot'
    }])
    prod = execute('product.product', 'search_read', [[['product_tmpl_id', '=', tmpl_id]]], {'fields': ['id'], 'limit': 1})
    return prod[0]['id']

# Create products
p_pellets = create_product("Raw Polymer Pellets")
p_blue_dye = create_product("Blue Industrial Dye")
p_red_dye = create_product("Red Industrial Dye")
p_yel_dye = create_product("Yellow Industrial Dye")
p_block = create_product("Polymer Block - Premium Blue")

# Helper to create lot
def create_lot(name, product_id):
    existing = execute('stock.lot', 'search_read', [[['name', '=', name], ['product_id', '=', product_id]]], {'fields': ['id']})
    if existing:
        return existing[0]['id']
    return execute('stock.lot', 'create', [{'name': name, 'product_id': product_id}])

# Create lots
l_pp1001 = create_lot('PP-1001', p_pellets)
l_pp1002 = create_lot('PP-1002', p_pellets)
l_blu77 = create_lot('DYE-BLU-77', p_blue_dye)
l_red42 = create_lot('DYE-RED-42', p_red_dye)
l_yel19 = create_lot('DYE-YEL-19', p_yel_dye)

# Clear existing quants for these products to ensure clean state
execute('stock.quant', 'search', [[['product_id', 'in', [p_pellets, p_blue_dye, p_red_dye, p_yel_dye, p_block]]]])

# Helper to set initial inventory
def set_initial_stock(product_id, lot_id, qty):
    quant_id = execute('stock.quant', 'create', [{
        'product_id': product_id,
        'location_id': stock_loc_id,
        'lot_id': lot_id,
        'inventory_quantity': qty
    }])
    execute('stock.quant', 'action_apply_inventory', [[quant_id]])

# Apply initial stock
set_initial_stock(p_pellets, l_pp1001, 5000)
set_initial_stock(p_pellets, l_pp1002, 1200)
set_initial_stock(p_blue_dye, l_blu77, 100)
set_initial_stock(p_red_dye, l_red42, 40)
set_initial_stock(p_yel_dye, l_yel19, 30)

print("Test data injected successfully.")
PYEOF

    date +%s > /tmp/task_start_timestamp

    # Open Firefox
    if ! pgrep -f firefox > /dev/null; then
        echo "Starting Firefox..."
        su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' > /dev/null 2>&1 &"
        sleep 5
    fi

    # Maximize and Focus
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    take_screenshot /tmp/task_start.png ga

    echo "=== Task Setup Complete ==="
fi