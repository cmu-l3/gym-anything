#!/bin/bash
# Setup script for warehouse_putaway_rules
source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"
ODOO_USER="admin"
ODOO_PASS="admin"

echo "=== Setting up Warehouse Putaway Rules task ==="

# Detect actual PostgreSQL container name
PG_CONTAINER=""
for name in odoo-db odoo-postgres; do
    if docker exec "$name" pg_isready -U odoo 2>/dev/null; then
        PG_CONTAINER="$name"
        break
    fi
done

if [ -z "$PG_CONTAINER" ]; then
    echo "Starting Odoo containers..."
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

date +%s > /tmp/task_start_timestamp

if [ -n "$PG_CONTAINER" ]; then
    # Verify database usability
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    
    if [ "$DB_USABLE" != "1" ]; then
        echo "Initializing database..."
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
        sleep 10
    fi
    
    # Wait for Odoo web to be available
    echo "Waiting for Odoo web..."
    for _j in $(seq 1 60); do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && break
        sleep 3
    done
    
    # Wait for XML-RPC
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
        sleep 2
    done

    echo "Seeding task data via XML-RPC..."
    python3 << PYEOF
import xmlrpc.client
import time

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def execute(*args, **kwargs):
    return models.execute_kw(db, uid, password, *args, **kwargs)

# 1. Disable Storage Locations feature to ensure agent does it
ir_model_data = execute('ir.model.data', 'search_read', 
    [[['module', '=', 'stock'], ['name', '=', 'group_stock_multi_locations']]], 
    {'fields': ['res_id']})
if ir_model_data:
    group_id = ir_model_data[0]['res_id']
    execute('res.users', 'write', [[uid], {'groups_id': [(3, group_id)]}])

# 2. Create Categories
categ_names = ['Power Tools', 'Hand Tools', 'Fasteners']
categ_ids = {}
for name in categ_names:
    c_ids = execute('product.category', 'search', [[['name', '=', name]]])
    if not c_ids:
        c_id = execute('product.category', 'create', [{'name': name}])
    else:
        c_id = c_ids[0]
    categ_ids[name] = c_id

# 3. Create Products
products = [
    ('DeWalt DCD771C2 20V MAX Cordless Drill/Driver Kit', 'Power Tools'),
    ('Makita XFD131 18V LXT Lithium-Ion Drill/Driver', 'Power Tools'),
    ('Stanley 92-839 Black Chrome Socket Set', 'Hand Tools'),
    ('Channellock 430 10" Tongue & Groove Plier', 'Hand Tools'),
    ('GRK R4 Multi-Purpose Screw 9x2.5in 100ct', 'Fasteners'),
    ('Simpson Strong-Tie SD9112R100 Structural Screw 100ct', 'Fasteners')
]

for p_name, c_name in products:
    p_ids = execute('product.template', 'search', [[['name', '=', p_name]]])
    if not p_ids:
        execute('product.template', 'create', [{
            'name': p_name,
            'categ_id': categ_ids[c_name],
            'type': 'product',
            'detailed_type': 'product'
        }])

# 4. Clean up any existing sub-locations and putaway rules
rules = execute('stock.putaway.rule', 'search', [[]])
if rules:
    execute('stock.putaway.rule', 'unlink', [rules])

loc_names = ['Zone A - Power Tools', 'Zone B - Hand Tools', 'Zone C - Fasteners']
locs = execute('stock.location', 'search', [[['name', 'in', loc_names]]])
if locs:
    try:
        execute('stock.location', 'unlink', [locs])
    except:
        execute('stock.location', 'write', [locs, {'active': False}])

print("Data seeding complete.")
PYEOF

else
    echo "WARNING: Could not connect to database for setup."
fi

# Start Firefox and navigate to Odoo
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox http://localhost:8069/web &"
    sleep 5
fi

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="