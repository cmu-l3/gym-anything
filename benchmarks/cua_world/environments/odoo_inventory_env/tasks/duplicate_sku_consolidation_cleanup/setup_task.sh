#!/bin/bash
# Setup script for Janitorial SKU Consolidation and Cleanup

source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"
ODOO_USER="admin"
ODOO_PASS="admin"

echo "=== Setting up Janitorial SKU Consolidation Task ==="
date +%s > /tmp/janitorial_cleanup_task_start
rm -f /tmp/janitorial_cleanup_result.json

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
    echo "FATAL: PostgreSQL container unavailable."
    exit 1
fi

# Basic DB Init checks (standard for odoo_inventory_env)
DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
if [ "$DB_USABLE" != "1" ]; then
    echo "Database '${ODOO_DB}' not usable. Recreating..."
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
    docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" -i base,stock,sale_management,purchase --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true
    docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
    docker restart odoo-web 2>/dev/null || true
    sleep 15
fi

# Wait for Odoo to be fully ready
echo "Waiting for Odoo XML-RPC..."
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

echo "Odoo API ready. Injecting janitorial catalog data..."

# Python script to load the test data into Odoo
python3 << PYEOF
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_inventory'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Get standard warehouse stock location
    wh = models.execute_kw(db, uid, password, 'stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
    if not wh:
        print("ERROR: No warehouse found.")
        sys.exit(1)
    loc_id = wh[0]['lot_stock_id'][0]

    products_to_create = [
        # Masters
        {"name": "Commercial Glass Cleaner 1 Gal", "code": "JAN-001", "qty": 10, "desc": "Standard 1 gallon glass cleaner."},
        {"name": "Heavy Duty Degreaser 5 Gal", "code": "JAN-002", "qty": 5, "desc": "Industrial degreaser for shop floors."},
        {"name": "Toilet Bowl Cleaner 32oz", "code": "JAN-003", "qty": 20, "desc": "Standard bathroom cleaner."},
        
        # Duplicates
        {"name": "1G Glass Cleaner", "code": "JAN-001-DUP", "qty": 15, "desc": "Duplicate of JAN-001. Please consolidate."},
        {"name": "Degreaser 5G", "code": "JAN-002-DUP", "qty": 10, "desc": "Duplicate of JAN-002. Please consolidate."},
        {"name": "TB Cleaner 32oz", "code": "JAN-003-DUP", "qty": 12, "desc": "Duplicate of JAN-003. Please consolidate."},
        
        # Unrelated
        {"name": "Trash Bags 33 Gallon Black", "code": "JAN-004", "qty": 50, "desc": "Heavy duty 33G trash bags (box of 100)."},
        {"name": "Microfiber Cleaning Cloths (50 pack)", "code": "JAN-005", "qty": 30, "desc": "Washable microfiber towels."},
        {"name": "Pine-Sol All Purpose Cleaner 144oz", "code": "JAN-006", "qty": 25, "desc": "Multi-surface cleaner."},
        {"name": "Wet Floor Sign", "code": "JAN-007", "qty": 5, "desc": "Yellow A-frame wet floor warning sign."}
    ]

    for p in products_to_create:
        # Check if exists to avoid errors on retry
        existing = models.execute_kw(db, uid, password, 'product.template', 'search', [[['default_code', '=', p['code']], ['active', 'in', [True, False]]]])
        if existing:
            # Delete old duplicate if re-running
            models.execute_kw(db, uid, password, 'product.template', 'unlink', [existing])
            
        # Create product template
        tmpl_id = models.execute_kw(db, uid, password, 'product.template', 'create', [{
            'name': p['name'],
            'default_code': p['code'],
            'type': 'product',
            'description': p['desc']
        }])
        
        # Get product variant ID
        tmpl = models.execute_kw(db, uid, password, 'product.template', 'read', [[tmpl_id]], {'fields': ['product_variant_ids']})
        prod_id = tmpl[0]['product_variant_ids'][0]
        
        # Set initial stock
        quant_id = models.execute_kw(db, uid, password, 'stock.quant', 'create', [{
            'product_id': prod_id,
            'location_id': loc_id,
            'inventory_quantity': p['qty']
        }])
        models.execute_kw(db, uid, password, 'stock.quant', 'action_apply_inventory', [[quant_id]])
        
    print("Catalog data injected successfully.")
except Exception as e:
    print(f"Failed to inject data: {e}")
PYEOF

take_screenshot /tmp/janitorial_cleanup_start.png

echo "=== Task Setup Complete ==="