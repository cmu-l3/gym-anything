#!/bin/bash
# Note: no set -euo pipefail — commands need to be fault-tolerant

source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"
ODOO_USER="admin"
ODOO_PASS="admin"

# Detect actual PostgreSQL container name (checkpoint may differ from docker-compose)
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

date +%s > /tmp/roof_leak_task_start_timestamp
rm -f /tmp/roof_leak_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Verify database is actually usable
    echo "Checking database usability..."
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')

    if [ "$DB_USABLE" != "1" ]; then
        echo "Database '${ODOO_DB}' not usable. Dropping and recreating..."
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
        sleep 2
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        sleep 2

        # Verify the DB was created
        DB_CREATED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')

        if [ "$DB_CREATED" = "1" ]; then
            echo "Initializing Odoo modules (this may take 3-5 minutes)..."
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
        sleep 10
    else
        echo "Database '${ODOO_DB}' is usable."
        
        # Check modules
        MODULES_INSTALLED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc \
            "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null | tr -d ' \n')
        
        if [ "$MODULES_INSTALLED" != "1" ] && [ "$MODULES_INSTALLED" != "" ]; then
            echo "Modules not installed. Running module init..."
            docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
                -i base,stock,sale_management,purchase \
                --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -10 || true
            docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
                -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
            docker restart odoo-web 2>/dev/null || true
            sleep 10
        fi
    fi

    # Wait for Odoo web registry to load
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

    # Load Data via XML-RPC
    echo "Loading scenario data..."
    python3 << 'PYEOF'
import xmlrpc.client, sys

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = common.authenticate(db, 'admin', password, {})
if not uid:
    print("XML-RPC Auth failed.")
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs or {})

# Enable multi-locations
group_id = execute('ir.model.data', 'xmlid_to_res_id', ['stock.group_stock_multi_locations'])
if group_id:
    execute('res.users', 'write', [[uid], {'groups_id': [(4, group_id)]}])

# Find main warehouse
wh = execute('stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
if not wh:
    print("No warehouse found.")
    sys.exit(1)
stock_loc_id = wh[0]['lot_stock_id'][0]

def create_loc(name):
    existing = execute('stock.location', 'search_read', [[['name', '=', name], ['location_id', '=', stock_loc_id]]], {'limit': 1})
    if existing: return existing[0]['id']
    return execute('stock.location', 'create', [{'name': name, 'location_id': stock_loc_id, 'usage': 'internal'}])

aisle_c_b1 = create_loc('Aisle C/Bay 1')
aisle_c_b2 = create_loc('Aisle C/Bay 2')
aisle_d_b1 = create_loc('Aisle D/Bay 1')
aisle_a_b3 = create_loc('Aisle A/Bay 3')
aisle_b_b1 = create_loc('Aisle B/Bay 1')

# Create products
product_defs = [
    {'name': 'Henry 208R Rubberized Wet Patch', 'code': 'BLD-WP-001', 'desc': 'Packaging: Plastic Gallon Bucket\nNote: Store upright.'},
    {'name': 'SharkBite 1/2 in. Brass Coupling', 'code': 'BLD-WP-002', 'desc': 'Packaging: Sealed Plastic Bag\nNote: Plumbing aisle.'},
    {'name': 'Southwire 250 ft. 12/2 Romex', 'code': 'BLD-WP-003', 'desc': 'Packaging: Shrink-wrapped Nylon Coil\nNote: Heavy.'},
    {'name': 'USG Sheetrock All-Purpose Compound', 'code': 'BLD-VS-001', 'desc': 'Packaging: Cardboard Carton\nNote: Keep dry.'},
    {'name': 'Kraft Paper Roll 36-inch x 1000ft', 'code': 'BLD-VS-002', 'desc': 'Packaging: Paper\nNote: General masking.'},
    {'name': 'Owens Corning R-13 Insulation', 'code': 'BLD-VS-003', 'desc': 'Packaging: Kraft-faced\nNote: Fiberglass warning.'},
]

prod_map = {}
for p in product_defs:
    existing = execute('product.template', 'search_read', [[['default_code', '=', p['code']]]], {'fields': ['product_variant_ids'], 'limit': 1})
    if existing:
        prod_id = existing[0]['product_variant_ids'][0]
        # Ensure description is set
        execute('product.template', 'write', [[existing[0]['id']], {'description': p['desc']}])
    else:
        tmpl_id = execute('product.template', 'create', [{
            'name': p['name'], 
            'default_code': p['code'], 
            'type': 'product', 
            'description': p['desc']
        }])
        tmpl = execute('product.template', 'read', [[tmpl_id]], {'fields': ['product_variant_ids']})
        prod_id = tmpl[0]['product_variant_ids'][0]
    prod_map[p['code']] = prod_id

stock_placements = [
    {'code': 'BLD-WP-001', 'loc': aisle_c_b1, 'qty': 60},
    {'code': 'BLD-WP-002', 'loc': aisle_c_b2, 'qty': 150},
    {'code': 'BLD-WP-003', 'loc': aisle_c_b2, 'qty': 30},
    {'code': 'BLD-VS-001', 'loc': aisle_c_b1, 'qty': 40},
    {'code': 'BLD-VS-002', 'loc': aisle_c_b2, 'qty': 15},
    {'code': 'BLD-VS-003', 'loc': aisle_c_b1, 'qty': 25},
    {'code': 'BLD-VS-001', 'loc': aisle_b_b1, 'qty': 100},
    {'code': 'BLD-WP-002', 'loc': aisle_a_b3, 'qty': 50},
]

# Clear existing stock to prevent duplications if restarted
for code in prod_map:
    quants = execute('stock.quant', 'search', [[['product_id', '=', prod_map[code]]]])
    if quants:
        execute('stock.quant', 'unlink', [quants])

# Apply inventory quantities
for sp in stock_placements:
    quant_id = execute('stock.quant', 'create', [{
        'product_id': prod_map[sp['code']],
        'location_id': sp['loc'],
        'inventory_quantity': sp['qty']
    }])
    execute('stock.quant', 'action_apply_inventory', [[quant_id]])

print("Scenario data loaded.")
PYEOF
fi

# Initial screenshot
take_screenshot "/tmp/roof_leak_task_start.png" || true
echo "Setup complete."