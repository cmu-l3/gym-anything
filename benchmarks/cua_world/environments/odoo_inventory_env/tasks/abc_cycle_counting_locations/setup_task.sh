#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up abc_cycle_counting_locations task ==="

ODOO_DB="odoo_inventory"

# Detect PG container
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

date +%s > /tmp/task_start_time.txt
rm -f /tmp/abc_cycle_counting_locations_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Check DB usable
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    
    if [ "$DB_USABLE" != "1" ]; then
        echo "Database not usable. Dropping and recreating..."
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
    
    # Wait for web and XMLRPC
    for _j in $(seq 1 30); do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && break
        sleep 2
    done
    
    for _k in $(seq 1 15); do
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

    # Run setup via XMLRPC
    python3 << PYEOF
import xmlrpc.client, sys

url = 'http://localhost:8069'
db = '${ODOO_DB}'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    # Disable Storage Locations feature
    settings_id = execute('res.config.settings', 'create', [{'group_stock_multi_locations': False}])
    execute('res.config.settings', 'execute', [[settings_id]])

    # Get WH/Stock location
    wh = execute('stock.warehouse', 'search_read', [[]], fields=['lot_stock_id'], limit=1)
    if not wh:
        print("No warehouse found!")
        sys.exit(1)
    wh_stock_loc_id = wh[0]['lot_stock_id'][0]

    # Archive existing zones to avoid confusion
    zones = execute('stock.location', 'search', [[('name', 'in', ['Zone A', 'Zone B', 'Zone C'])]])
    if zones:
        execute('stock.location', 'write', [zones, {'active': False, 'name': 'Archived Zone'}])

    # Create/update products
    products_data = [
        {'name': 'NVIDIA RTX 4090 GPU', 'default_code': 'ABC-A-001', 'type': 'product', 'qty': 10},
        {'name': 'ASUS ROG Crosshair X670E Hero', 'default_code': 'ABC-B-001', 'type': 'product', 'qty': 50},
        {'name': 'Southwire Cat6 CMP Plenum 1000ft', 'default_code': 'ABC-C-001', 'type': 'product', 'qty': 200},
    ]

    for p in products_data:
        prod_tmpl = execute('product.template', 'search', [[('default_code', '=', p['default_code'])]])
        if not prod_tmpl:
            tmpl_id = execute('product.template', 'create', [{
                'name': p['name'],
                'default_code': p['default_code'],
                'detailed_type': p['type'],
            }])
        else:
            tmpl_id = prod_tmpl[0]
            
        prod = execute('product.product', 'search', [[('product_tmpl_id', '=', tmpl_id)]])
        prod_id = prod[0]
        
        # Set inventory quantity
        quant = execute('stock.quant', 'search', [[('product_id', '=', prod_id), ('location_id', '=', wh_stock_loc_id)]])
        if not quant:
            quant_id = execute('stock.quant', 'create', [{
                'product_id': prod_id,
                'location_id': wh_stock_loc_id,
                'inventory_quantity': p['qty'],
            }])
            execute('stock.quant', 'action_apply_inventory', [[quant_id]])
        else:
            execute('stock.quant', 'write', [quant, {'inventory_quantity': p['qty']}])
            execute('stock.quant', 'action_apply_inventory', [quant])

        # Remove stock from any other location
        other_quants = execute('stock.quant', 'search', [[('product_id', '=', prod_id), ('location_id', '!=', wh_stock_loc_id)]])
        if other_quants:
            execute('stock.quant', 'write', [other_quants, {'inventory_quantity': 0}])
            execute('stock.quant', 'action_apply_inventory', [other_quants])
            
    print("Setup completed successfully.")
except Exception as e:
    print(f"Setup failed: {e}")
PYEOF

fi

# Start Firefox and maximize
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Odoo"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="