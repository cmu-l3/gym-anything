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

date +%s > /tmp/vendor_disruption_task_start_timestamp
rm -f /tmp/vendor_disruption_pivot_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Verify database is actually usable
    echo "Checking database usability..."
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    echo "DB_USABLE='${DB_USABLE}'"

    if [ "$DB_USABLE" != "1" ]; then
        echo "Database '${ODOO_DB}' not usable. Dropping and recreating..."
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
        sleep 2
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        sleep 2

        # Verify the DB was created
        DB_CREATED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
        echo "DB created check: '${DB_CREATED}'"

        if [ "$DB_CREATED" = "1" ]; then
            echo "Initializing Odoo modules (this may take 3-5 minutes)..."
            # Pass -c /etc/odoo/odoo.conf so Odoo uses TCP to reach the db container
            docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
                -i base,stock,sale_management,purchase \
                --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true

            # Verify modules installed
            MODULES_OK=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc \
                "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null | tr -d ' \n')
            echo "Modules installed: ${MODULES_OK}"

            # Set admin credentials
            docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
                -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        else
            echo "ERROR: Could not create database."
        fi

        # Restart Odoo web to pick up the new database
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
    else
        echo "Database '${ODOO_DB}' is usable."

        # Check if modules are installed
        MODULES_INSTALLED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc \
            "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null | tr -d ' \n')
        echo "Modules installed: ${MODULES_INSTALLED}"

        if [ "$MODULES_INSTALLED" != "1" ] && [ "$MODULES_INSTALLED" != "" ]; then
            echo "Modules not installed. Running module init..."
            docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
                -i base,stock,sale_management,purchase \
                --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -10 || true
            docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
                -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        fi

        # Restart Odoo web to force registry reload
        echo "Restarting Odoo web to reload module registry..."
        docker restart odoo-web 2>/dev/null || true
        for _r in $(seq 1 60); do
            HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
            [ "$HTTP" = "200" ] && break
            sleep 5
        done
        sleep 10
    fi
fi

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${ODOO_URL}/web/login" 2>/dev/null || echo "000")
    [ "$HTTP_CODE" = "200" ] && break
    sleep 3
done

# --- Setup via Python XML-RPC ---
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = None
for attempt in range(6):
    try:
        uid = common.authenticate(db, 'admin', password, {})
        if uid:
            print(f"Auth OK (attempt {attempt+1}): uid={uid}")
            break
    except Exception as e:
        print(f"Auth attempt {attempt+1} failed: {e}", file=sys.stderr)
    time.sleep(5)

if not uid:
    print("Auth failed after retries", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

# Get warehouse and stock location
warehouses = execute('stock.warehouse', 'search_read', [[]],
                     fields=['id', 'lot_stock_id'], limit=1)
if not warehouses:
    print("No warehouse found", file=sys.stderr)
    sys.exit(1)
wh = warehouses[0]
wh_id = wh['id']
stock_loc_id = wh['lot_stock_id'][0]

# ============================================================
# Create 3 vendors
# ============================================================

# Vendor 1: Precision Aeroparts Inc. (DISRUPTED)
vendors = execute('res.partner', 'search_read',
                  [[['name', '=', 'Precision Aeroparts Inc.']]],
                  fields=['id'], limit=1)
if vendors:
    precision_id = vendors[0]['id']
else:
    precision_id = execute('res.partner', 'create', [{
        'name': 'Precision Aeroparts Inc.',
        'supplier_rank': 1,
        'street': '7500 Aviation Way',
        'city': 'Wichita',
        'state_id': False,
        'country_id': 233,
        'phone': '316-555-0300',
        'email': 'sales@precisionaeroparts.com',
        'comment': 'VENDOR ALERT: Force majeure declared 2024-02-28. All pending orders suspended indefinitely. Activate backup suppliers for all products immediately. Ref: PROC-2024-FM-001',
    }])
# Ensure the internal note is set even if vendor already existed
execute('res.partner', 'write', [[precision_id], {
    'comment': 'VENDOR ALERT: Force majeure declared 2024-02-28. All pending orders suspended indefinitely. Activate backup suppliers for all products immediately. Ref: PROC-2024-FM-001',
}])

# Vendor 2: SkyTech Components Ltd.
vendors = execute('res.partner', 'search_read',
                  [[['name', '=', 'SkyTech Components Ltd.']]],
                  fields=['id'], limit=1)
if vendors:
    skytech_id = vendors[0]['id']
else:
    skytech_id = execute('res.partner', 'create', [{
        'name': 'SkyTech Components Ltd.',
        'supplier_rank': 1,
        'street': '2100 Aerospace Blvd',
        'city': 'Seattle',
        'state_id': False,
        'country_id': 233,
        'phone': '206-555-0400',
        'email': 'orders@skytechcomponents.com',
    }])

# Vendor 3: AeroAlloy Materials Corp.
vendors = execute('res.partner', 'search_read',
                  [[['name', '=', 'AeroAlloy Materials Corp.']]],
                  fields=['id'], limit=1)
if vendors:
    aeroalloy_id = vendors[0]['id']
else:
    aeroalloy_id = execute('res.partner', 'create', [{
        'name': 'AeroAlloy Materials Corp.',
        'supplier_rank': 1,
        'street': '4400 Metallurgy Dr',
        'city': 'Pittsburgh',
        'state_id': False,
        'country_id': 233,
        'phone': '412-555-0500',
        'email': 'procurement@aeroalloy.com',
    }])

pass  # vendors created

# ============================================================
# Define 10 products with vendor and PO details
# ============================================================
products = [
    # Products 1-4: Primary vendor = Precision Aeroparts (disrupted), with backup vendors
    {
        'code': 'AERO-BRK-001', 'name': 'Landing Gear Brake Assembly',
        'price': 2400.00, 'stock': 12,
        'primary_vendor': precision_id, 'primary_price': 2400.00,
        'backup_vendor': skytech_id, 'backup_price': 2650.00,
        'pending_po_qty': 25, 'pending_po_state': 'draft',
    },
    {
        'code': 'AERO-HYD-002', 'name': 'Hydraulic Actuator Servo Unit',
        'price': 1850.00, 'stock': 8,
        'primary_vendor': precision_id, 'primary_price': 1850.00,
        'backup_vendor': skytech_id, 'backup_price': 2100.00,
        'pending_po_qty': 40, 'pending_po_state': 'draft',
    },
    {
        'code': 'AERO-TRB-003', 'name': 'Turbine Blade Set Grade-5 Titanium',
        'price': 8500.00, 'stock': 5,
        'primary_vendor': precision_id, 'primary_price': 8500.00,
        'backup_vendor': aeroalloy_id, 'backup_price': 9200.00,
        'pending_po_qty': 15, 'pending_po_state': 'sent',
    },
    {
        'code': 'AERO-FAS-004', 'name': 'Fuselage Fastener Kit AN-Series',
        'price': 340.00, 'stock': 200,
        'primary_vendor': precision_id, 'primary_price': 340.00,
        'backup_vendor': aeroalloy_id, 'backup_price': 380.00,
        'pending_po_qty': 100, 'pending_po_state': 'draft',
    },
    # Products 5-7: Primary vendor = SkyTech, no backup, some with POs
    {
        'code': 'AERO-AVN-005', 'name': 'Avionics Wiring Harness Set',
        'price': 1200.00, 'stock': 15,
        'primary_vendor': skytech_id, 'primary_price': 1200.00,
        'backup_vendor': None, 'backup_price': None,
        'pending_po_qty': None, 'pending_po_state': None,
    },
    {
        'code': 'AERO-CMP-006', 'name': 'Composite Panel 4x8 Carbon Fiber',
        'price': 950.00, 'stock': 30,
        'primary_vendor': skytech_id, 'primary_price': 950.00,
        'backup_vendor': None, 'backup_price': None,
        'pending_po_qty': 20, 'pending_po_state': 'purchase',  # CONFIRMED - must not touch
    },
    {
        'code': 'AERO-RVT-007', 'name': 'Rivet Set Cherry-Max 500ct',
        'price': 185.00, 'stock': 500,
        'primary_vendor': skytech_id, 'primary_price': 185.00,
        'backup_vendor': None, 'backup_price': None,
        'pending_po_qty': None, 'pending_po_state': None,
    },
    # Products 8-10: Primary vendor = AeroAlloy, no backup, some with POs
    {
        'code': 'AERO-BRG-008', 'name': 'Turbine Bearing Set ABEC-7',
        'price': 720.00, 'stock': 25,
        'primary_vendor': aeroalloy_id, 'primary_price': 720.00,
        'backup_vendor': None, 'backup_price': None,
        'pending_po_qty': None, 'pending_po_state': None,
    },
    {
        'code': 'AERO-SEL-009', 'name': 'Seal Kit Viton O-Ring Assortment',
        'price': 95.00, 'stock': 100,
        'primary_vendor': aeroalloy_id, 'primary_price': 95.00,
        'backup_vendor': None, 'backup_price': None,
        'pending_po_qty': 50, 'pending_po_state': 'purchase',  # CONFIRMED - must not touch
    },
    {
        'code': 'AERO-SHM-010', 'name': 'Shim Set Stainless 0.001-0.025',
        'price': 145.00, 'stock': 75,
        'primary_vendor': aeroalloy_id, 'primary_price': 145.00,
        'backup_vendor': None, 'backup_price': None,
        'pending_po_qty': None, 'pending_po_state': None,
    },
]

product_ids = {}  # code -> (tmpl_id, prod_id)

for prod in products:
    existing = execute('product.template', 'search_read',
                       [[['default_code', '=', prod['code']]]],
                       fields=['id', 'product_variant_ids'], limit=1)
    if existing:
        tmpl_id = existing[0]['id']
        prod_id = existing[0]['product_variant_ids'][0]
    else:
        tmpl_id = execute('product.template', 'create', [{
            'name': prod['name'],
            'default_code': prod['code'],
            'detailed_type': 'product',
            'list_price': prod['price'],
            'standard_price': prod['price'],
            'purchase_ok': True,
            'sale_ok': False,
            'tracking': 'none',
        }])
        variants = execute('product.template', 'read', [[tmpl_id]], fields=['product_variant_ids'])
        prod_id = variants[0]['product_variant_ids'][0]

    product_ids[prod['code']] = (tmpl_id, prod_id)

    # Primary vendor pricelist
    existing_suppliers = execute('product.supplierinfo', 'search',
                                 [[['product_tmpl_id', '=', tmpl_id],
                                   ['partner_id', '=', prod['primary_vendor']]]])
    if not existing_suppliers:
        execute('product.supplierinfo', 'create', [{
            'product_tmpl_id': tmpl_id,
            'partner_id': prod['primary_vendor'],
            'price': prod['primary_price'],
            'min_qty': 1,
            'delay': 7,
            'sequence': 1,
        }])

    # Backup vendor pricelist (if applicable)
    if prod['backup_vendor']:
        existing_backup = execute('product.supplierinfo', 'search',
                                   [[['product_tmpl_id', '=', tmpl_id],
                                     ['partner_id', '=', prod['backup_vendor']]]])
        if not existing_backup:
            execute('product.supplierinfo', 'create', [{
                'product_tmpl_id': tmpl_id,
                'partner_id': prod['backup_vendor'],
                'price': prod['backup_price'],
                'min_qty': 1,
                'delay': 10,
                'sequence': 2,
            }])

    # Stock quantity
    quants = execute('stock.quant', 'search',
                     [[['product_id', '=', prod_id], ['location_id', '=', stock_loc_id]]])
    if quants:
        execute('stock.quant', 'write', [quants, {'inventory_quantity': prod['stock']}])
        try:
            execute('stock.quant', 'action_apply_inventory', [quants])
        except Exception:
            pass  # action succeeds server-side; XML-RPC may fail to serialize None response
    else:
        q_id = execute('stock.quant', 'create', [{
            'product_id': prod_id,
            'location_id': stock_loc_id,
            'inventory_quantity': prod['stock'],
        }])
        try:
            execute('stock.quant', 'action_apply_inventory', [[q_id]])
        except Exception:
            pass  # action succeeds server-side; XML-RPC may fail to serialize None response

    # Remove existing reorder rules for this product
    existing_rules = execute('stock.warehouse.orderpoint', 'search',
                             [[['product_id', '=', prod_id]]])
    if existing_rules:
        execute('stock.warehouse.orderpoint', 'unlink', [existing_rules])

    # Remove existing draft/sent POs for this product
    po_lines = execute('purchase.order.line', 'search',
                       [[['product_id', '=', prod_id],
                         ['order_id.state', 'in', ['draft', 'sent']]]])
    if po_lines:
        po_ids_list = [l['order_id'][0] for l in execute('purchase.order.line', 'read',
                                                           [po_lines], fields=['order_id'])]
        for po_id in set(po_ids_list):
            try:
                execute('purchase.order', 'button_cancel', [[po_id]])
            except Exception:
                pass

print("Data seeding complete.")

# Group affected POs by vendor for realistic PO creation (one PO per vendor)
# Products 1-4: individual POs from Precision Aeroparts (disrupted vendor)
affected_products = [p for p in products if p['pending_po_qty'] and p['primary_vendor'] == precision_id]
for prod in affected_products:
    tmpl_id, prod_id = product_ids[prod['code']]
    po_id = execute('purchase.order', 'create', [{
        'partner_id': precision_id,
        'order_line': [(0, 0, {
            'product_id': prod_id,
            'product_qty': prod['pending_po_qty'],
            'price_unit': prod['primary_price'],
            'name': prod['name'],
            'date_planned': '2024-03-15',
        })],
    }])
    # Set state for sent POs
    if prod['pending_po_state'] == 'sent':
        execute('purchase.order', 'write', [[po_id], {'state': 'sent'}])
    pass  # PO created

# Product 6 (AERO-CMP-006): Confirmed PO from SkyTech - MUST NOT TOUCH
tmpl_id_006, prod_id_006 = product_ids['AERO-CMP-006']
po_cmp = execute('purchase.order', 'create', [{
    'partner_id': skytech_id,
    'order_line': [(0, 0, {
        'product_id': prod_id_006,
        'product_qty': 20,
        'price_unit': 950.00,
        'name': 'Composite Panel 4x8 Carbon Fiber',
        'date_planned': '2024-03-20',
    })],
}])
try:
    execute('purchase.order', 'button_confirm', [[po_cmp]])
except Exception:
    pass  # action succeeds server-side; XML-RPC may fail to serialize None response
pass  # protected PO created

# Product 9 (AERO-SEL-009): Confirmed PO from AeroAlloy - MUST NOT TOUCH
tmpl_id_009, prod_id_009 = product_ids['AERO-SEL-009']
po_sel = execute('purchase.order', 'create', [{
    'partner_id': aeroalloy_id,
    'order_line': [(0, 0, {
        'product_id': prod_id_009,
        'product_qty': 50,
        'price_unit': 95.00,
        'name': 'Seal Kit Viton O-Ring Assortment',
        'date_planned': '2024-03-25',
    })],
}])
try:
    execute('purchase.order', 'button_confirm', [[po_sel]])
except Exception:
    pass  # action succeeds server-side; XML-RPC may fail to serialize None response
pass  # protected PO created

# ============================================================
# Create reorder rules for affected products pointing to disrupted vendor
# ============================================================
pass  # creating reorder rules

reorder_configs = {
    'AERO-BRK-001': {'min_qty': 10, 'max_qty': 50},
    'AERO-HYD-002': {'min_qty': 5, 'max_qty': 30},
    'AERO-TRB-003': {'min_qty': 3, 'max_qty': 20},
    'AERO-FAS-004': {'min_qty': 100, 'max_qty': 500},
}

for code, config in reorder_configs.items():
    tmpl_id, prod_id = product_ids[code]
    # Get the buy route
    buy_routes = execute('stock.route', 'search', [[['name', 'ilike', 'Buy']]])
    rule_id = execute('stock.warehouse.orderpoint', 'create', [{
        'product_id': prod_id,
        'warehouse_id': wh_id,
        'location_id': stock_loc_id,
        'product_min_qty': config['min_qty'],
        'product_max_qty': config['max_qty'],
        'qty_multiple': 1,
    }])
    pass  # rule created

print("Setup data complete.")
PYEOF

# Record initial state for anti-gaming
python3 << 'PYEOF2'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'
common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

initial_state = {}
all_codes = [
    'AERO-BRK-001', 'AERO-HYD-002', 'AERO-TRB-003', 'AERO-FAS-004',
    'AERO-AVN-005', 'AERO-CMP-006', 'AERO-RVT-007', 'AERO-BRG-008',
    'AERO-SEL-009', 'AERO-SHM-010',
]

wh = execute('stock.warehouse', 'search_read', [[]], fields=['lot_stock_id'], limit=1)
stock_loc_id = wh[0]['lot_stock_id'][0]

# Record PO states for each product
for code in all_codes:
    tmpl = execute('product.template', 'search_read',
                   [[['default_code', '=', code]]], fields=['id', 'product_variant_ids'], limit=1)
    if tmpl:
        prod_id = tmpl[0]['product_variant_ids'][0]
        quants = execute('stock.quant', 'search_read',
                         [[['product_id', '=', prod_id], ['location_id', '=', stock_loc_id]]],
                         fields=['quantity'])
        qty = sum(q['quantity'] for q in quants)

        # Record all POs for this product
        po_lines = execute('purchase.order.line', 'search_read',
                           [[['product_id', '=', prod_id]]],
                           fields=['order_id', 'product_qty'])
        po_details = []
        for line in po_lines:
            po_id = line['order_id'][0]
            po_data = execute('purchase.order', 'read', [[po_id]],
                              fields=['state', 'partner_id', 'name'])[0]
            po_details.append({
                'po_id': po_id,
                'po_name': po_data['name'],
                'state': po_data['state'],
                'partner_id': po_data['partner_id'][0],
                'partner_name': po_data['partner_id'][1],
                'qty': line['product_qty'],
            })

        initial_state[code] = {
            'product_id': prod_id,
            'qty': qty,
            'pos': po_details,
        }

with open('/tmp/vendor_disruption_initial_state.json', 'w') as f:
    json.dump(initial_state, f, indent=2)
print("Initial state recorded.")
PYEOF2

# Launch Firefox
pkill -u ga -f firefox 2>/dev/null || true
for _i in $(seq 1 10); do
    pgrep -u ga -f firefox > /dev/null || break
    sleep 1
done
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web#action=purchase.purchase_rfq' > /tmp/firefox_odoo.log 2>&1 &"
sleep 6

WID=$(get_firefox_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot "/tmp/vendor_disruption_start.png" || true

echo "=== Setup complete ==="
