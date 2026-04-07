#!/bin/bash
source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"
ODOO_USER="admin"
ODOO_PASS="admin"

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

date +%s > /tmp/job_site_task_start_timestamp
rm -f /tmp/job_site_staging_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    echo "Checking database usability..."
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    
    if [ "$DB_USABLE" != "1" ]; then
        echo "Database '${ODOO_DB}' not usable. Dropping and recreating..."
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

    # Ensure Odoo is ready
    for _j in $(seq 1 30); do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && break
        sleep 5
    done

    echo "Setting up realistic test data via XMLRPC..."
    python3 << PYEOF
import xmlrpc.client
import time

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

def get_connection():
    for _ in range(10):
        try:
            common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
            uid = common.authenticate(db, 'admin', password, {})
            if uid:
                models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)
                return uid, models
        except Exception:
            time.sleep(2)
    return None, None

uid, models = get_connection()
if not uid:
    print("Failed to connect via XMLRPC")
    sys.exit(1)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

# Create Vendor
vendor_id = execute('res.partner', 'create', [{'name': 'BuildMart Wholesale', 'supplier_rank': 1}])

# Create Products
products_data = [
    {'name': 'Heavy Duty Steel Beams', 'default_code': 'CONST-BEAM-01', 'type': 'product', 'list_price': 150.0, 'standard_price': 100.0},
    {'name': 'Portland Cement (50lb bags)', 'default_code': 'CONST-CEM-02', 'type': 'product', 'list_price': 15.0, 'standard_price': 10.0},
    {'name': 'Acoustic Ceiling Tiles (Box)', 'default_code': 'CONST-TILE-03', 'type': 'product', 'list_price': 45.0, 'standard_price': 30.0},
    {'name': 'Commercial Copper Wiring (100m spool)', 'default_code': 'CONST-WIRE-04', 'type': 'product', 'list_price': 200.0, 'standard_price': 150.0},
    {'name': 'Hazardous Material Containment Drum', 'default_code': 'CONST-HAZ-05', 'type': 'product', 'list_price': 85.0, 'standard_price': 60.0, 'description_picking': 'SAFETY HOLD: DO NOT DEPLOY TO JOB SITES WITHOUT MANAGER APPROVAL'},
]

prod_ids = {}
for p in products_data:
    tmpl_id = execute('product.template', 'create', [p])
    tmpl = execute('product.template', 'read', [[tmpl_id]], fields=['product_variant_id'])[0]
    prod_ids[p['default_code']] = tmpl['product_variant_id'][0]

# Setup Initial Stock
wh = execute('stock.warehouse', 'search_read', [[]], fields=['id', 'lot_stock_id'], limit=1)
stock_loc_id = wh[0]['lot_stock_id'][0]

initial_stock = {
    'CONST-BEAM-01': 20,
    'CONST-CEM-02': 80,
    'CONST-TILE-03': 0,
    'CONST-WIRE-04': 10,
    'CONST-HAZ-05': 5
}

for code, qty in initial_stock.items():
    if qty > 0:
        pid = prod_ids[code]
        quant_id = execute('stock.quant', 'create', [{'product_id': pid, 'location_id': stock_loc_id, 'inventory_quantity': qty}])
        execute('stock.quant', 'action_apply_inventory', [[quant_id]])

print("Test data setup complete.")
PYEOF

    echo "Taking initial screenshot..."
    su - ga -c "DISPLAY=:1 firefox http://localhost:8069/web/login > /dev/null 2>&1 &"
    sleep 5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    take_screenshot /tmp/job_site_initial.png
fi

echo "=== Setup complete ==="