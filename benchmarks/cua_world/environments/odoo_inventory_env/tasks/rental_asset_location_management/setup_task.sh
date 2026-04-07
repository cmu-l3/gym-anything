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
echo "PostgreSQL container: ${PG_CONTAINER:-NOT FOUND}"

date +%s > /tmp/rental_asset_task_start_timestamp
rm -f /tmp/rental_asset_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Verify database is actually usable
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
                -i base,stock,contacts \
                --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true

            docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
                -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        fi

        echo "Restarting Odoo web server..."
        docker restart odoo-web 2>/dev/null || true

        for _j in $(seq 1 90); do
            HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
            [ "$HTTP" = "200" ] && break
            sleep 5
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
            sleep 5
        done
    else
        echo "Database '${ODOO_DB}' is usable."
    fi

    # Execute Python script to inject task data via XMLRPC
    echo "Injecting Rental Assets task data..."
    python3 << 'PYEOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'
common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = common.authenticate(db, 'admin', password, {})

if not uid:
    print("Authentication failed")
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

try:
    # 1. Enable Serial/Lot Tracking
    settings_id = execute('res.config.settings', 'create', {'group_stock_tracking_lot': True})
    execute('res.config.settings', 'execute', [[settings_id]])
    
    # 2. Setup Locations
    wh = execute('stock.warehouse', 'search_read', [[]], fields=['lot_stock_id'], limit=1)
    if not wh:
        print("No warehouse found!")
        sys.exit(1)
    stock_loc_id = wh[0]['lot_stock_id'][0]

    rent_loc_id = execute('stock.location', 'create', {
        'name': 'Out on Rent',
        'location_id': stock_loc_id,
        'usage': 'internal'
    })
    
    maint_loc_id = execute('stock.location', 'create', {
        'name': 'Maintenance',
        'location_id': stock_loc_id,
        'usage': 'internal'
    })

    # 3. Create Products
    prod_red = execute('product.product', 'create', {'name': 'RED Komodo 6K Camera', 'type': 'product', 'tracking': 'serial'})
    prod_batt = execute('product.product', 'create', {'name': 'V-Mount Battery 98Wh', 'type': 'product', 'tracking': 'none'})
    prod_mix = execute('product.product', 'create', {'name': 'Sound Devices 833 Mixer', 'type': 'product', 'tracking': 'serial'})
    prod_mic = execute('product.product', 'create', {'name': 'Sennheiser MKH416 Boom Mic', 'type': 'product', 'tracking': 'none'})
    prod_sony = execute('product.product', 'create', {'name': 'Sony Venice 2 Camera', 'type': 'product', 'tracking': 'serial'})

    # 4. Create Initial Stock
    def add_stock(prod_id, loc_id, qty, lot_name=None):
        lot_id = False
        if lot_name:
            lot_id = execute('stock.lot', 'create', {
                'name': lot_name,
                'product_id': prod_id,
                'company_id': 1
            })
        quant_id = execute('stock.quant', 'create', {
            'product_id': prod_id,
            'location_id': loc_id,
            'inventory_quantity': qty,
            'lot_id': lot_id
        })
        execute('stock.quant', 'action_apply_inventory', [[quant_id]])

    # RED Komodos (Stock)
    for i in range(1, 6):
        add_stock(prod_red, stock_loc_id, 1, f'RED-KOM-00{i}')
    
    # Battery (Stock)
    add_stock(prod_batt, stock_loc_id, 50)
    
    # Mixers
    add_stock(prod_mix, stock_loc_id, 1, 'SD-MIX-012')
    add_stock(prod_mix, rent_loc_id, 1, 'SD-MIX-011')
    
    # Mics
    add_stock(prod_mic, stock_loc_id, 10)
    add_stock(prod_mic, rent_loc_id, 3)
    
    # Sony (Rent)
    add_stock(prod_sony, rent_loc_id, 1, 'SNY-VEN-001')

    # 5. Create Contacts with Instructions
    execute('res.partner', 'create', {
        'name': 'Starlight Productions',
        'comment': 'URGENT DISPATCH FOR STARLIGHT PRODUCTIONS: Please transfer 2x RED Komodo 6K Cameras (specifically serials RED-KOM-002 and RED-KOM-005) and 5x V-Mount Battery 98Wh to the "Out on Rent" location.'
    })
    
    execute('res.partner', 'create', {
        'name': 'Acme Corp',
        'comment': 'RETURN FROM ACME CORP: They are returning their gear today. Please move the Sound Devices 833 Mixer (Serial: SD-MIX-011) back to Stock. They are also returning 3x Sennheiser MKH416 Boom Mics, but one of them got dropped in a puddle and needs to go to the "Maintenance" location to be checked. The other 2 can go back to normal Stock.'
    })

    print("Task data injection complete.")
except Exception as e:
    print(f"Data setup error: {e}")
    sys.exit(1)
PYEOF

    echo "Restarting Odoo web to flush caches..."
    docker restart odoo-web 2>/dev/null || true
    sleep 10
fi

# Bring up Firefox
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' > /dev/null 2>&1 &"
    sleep 5
fi

# Focus & Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="