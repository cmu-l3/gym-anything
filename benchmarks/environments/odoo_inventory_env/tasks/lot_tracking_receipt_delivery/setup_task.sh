#!/bin/bash
# Setup script for Lot Tracking Receipt & Delivery task
# Creates 3 medical products WITHOUT lot tracking, creates vendor Medline Industries Inc.,
# and creates a confirmed purchase order ready for receipt

echo "=== Setting up Lot Tracking Receipt & Delivery ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type odoo_query &>/dev/null; then
    odoo_query() {
        docker exec odoo-postgres psql -U odoo -d odoo_inventory -t -A -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Ensure the odoo_inventory database is initialized
echo "Checking database status..."
DB_EXISTS=$(docker exec odoo-postgres psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='odoo_inventory'" 2>/dev/null)
if [ "$DB_EXISTS" != "1" ]; then
    echo "Database not found. Initializing Odoo database..."
    docker exec odoo-postgres psql -U odoo -d postgres -c "CREATE DATABASE odoo_inventory OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
    sleep 2
    docker exec odoo-web odoo -d odoo_inventory -i base,stock,sale_management,purchase \
        --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -10 || true
    docker restart odoo-web 2>/dev/null || docker-compose -f /home/ga/odoo/docker-compose.yml restart web 2>/dev/null || true
    sleep 20
else
    echo "Database odoo_inventory exists"
fi

# Wait for Odoo
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then echo "Odoo ready"; break; fi
    if [ "$i" = "60" ]; then
        echo "WARNING: Odoo not returning 200 after 300s (HTTP $HTTP_CODE). Proceeding anyway."
    else
        sleep 5
    fi
done

# Record timestamp EARLY so verifier can detect agent actions even if setup partly fails
date +%s > /tmp/task_start_timestamp

python3 << 'PYEOF'
import xmlrpc.client, sys, json

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, 'admin', password, {})
if not uid:
    print("ERROR: Authentication failed", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

# Get category and UOM
categ_ids = models.execute_kw(db, uid, password, 'product.category', 'search',
    [[['complete_name', '=', 'All']]])
categ_id = categ_ids[0] if categ_ids else 1

uom_ids = models.execute_kw(db, uid, password, 'uom.uom', 'search', [[['name', '=', 'Units']]])
uom_id = uom_ids[0] if uom_ids else 1

# Get WH/Stock location
loc_ids = models.execute_kw(db, uid, password, 'stock.location', 'search_read',
    [[['usage', '=', 'internal'], ['complete_name', 'like', '/Stock']]],
    {'fields': ['id', 'complete_name'], 'order': 'id asc', 'limit': 1})
if not loc_ids:
    loc_ids = models.execute_kw(db, uid, password, 'stock.location', 'search_read',
        [[['usage', '=', 'internal'], ['name', '=', 'Stock']]],
        {'fields': ['id'], 'limit': 1})
stock_loc_id = loc_ids[0]['id'] if loc_ids else None
if not stock_loc_id:
    print("ERROR: Could not find stock location", file=sys.stderr)
    sys.exit(1)

# Get or create vendor Medline Industries Inc.
vendor_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
    [[['name', '=', 'Medline Industries Inc.']]])
if vendor_ids:
    vendor_id = vendor_ids[0]
    print(f"Found vendor Medline Industries Inc. (id={vendor_id})")
else:
    vendor_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
        'name': 'Medline Industries Inc.',
        'supplier_rank': 1,
        'company_type': 'company',
        'email': 'orders@medline.com',
        'phone': '+1-800-633-5463',
        'street': '3 Lakes Drive',
        'city': 'Northfield',
        'zip': '60093',
        'country_id': 233,  # US
    }])
    print(f"Created vendor Medline Industries Inc. (id={vendor_id})")

# Products: real medical diagnostic / first-aid products, tracking set to NONE (agent must fix)
products_def = [
    {
        'name': 'Abbott FreeStyle Lite Test Strips 50ct',
        'code': 'LOT-TRACK-001',
        'price': 19.99,
        'cost': 12.50,
        'po_qty': 200.0,
        'lot': 'MED-2024-AB-001',
    },
    {
        'name': 'Braun ThermoScan Lens Filters LF40',
        'code': 'LOT-TRACK-002',
        'price': 8.49,
        'cost': 5.20,
        'po_qty': 150.0,
        'lot': 'MED-2024-BR-001',
    },
    {
        'name': '3M Nexcare Waterproof Bandages 30ct',
        'code': 'LOT-TRACK-003',
        'price': 6.99,
        'cost': 4.10,
        'po_qty': 300.0,
        'lot': 'MED-2024-3M-001',
    },
]

setup_info = {'vendor_id': vendor_id, 'stock_loc_id': stock_loc_id, 'products': {}, 'po_id': None}

prod_variant_map = {}

for prod in products_def:
    # Delete any existing PO for these products first (cleanup)
    existing_tmpl = models.execute_kw(db, uid, password, 'product.template', 'search_read',
        [[['default_code', '=', prod['code']]]], {'fields': ['id', 'tracking']})
    if existing_tmpl:
        tmpl_id = existing_tmpl[0]['id']
        # Reset tracking to none for the task start condition
        models.execute_kw(db, uid, password, 'product.template', 'write',
            [[tmpl_id], {'tracking': 'none'}])
        print(f"Reset {prod['code']} tracking to none")
    else:
        tmpl_id = models.execute_kw(db, uid, password, 'product.template', 'create', [{
            'name': prod['name'],
            'default_code': prod['code'],
            'detailed_type': 'product',
            'list_price': prod['price'],
            'categ_id': categ_id,
            'uom_id': uom_id,
            'uom_po_id': uom_id,
            'sale_ok': True,
            'purchase_ok': True,
            'tracking': 'none',  # INTENTIONALLY disabled — agent must enable
        }])
        print(f"Created product: {prod['name']} (tracking=none)")

    try:
        models.execute_kw(db, uid, password, 'product.template', 'write',
            [[tmpl_id], {'standard_price': prod['cost']}])
    except:
        pass

    prod_variant_ids = models.execute_kw(db, uid, password, 'product.product', 'search',
        [[['product_tmpl_id', '=', tmpl_id]]])
    prod_id = prod_variant_ids[0] if prod_variant_ids else None
    if not prod_id:
        print(f"ERROR: No variant for {prod['name']}", file=sys.stderr)
        continue

    prod_variant_map[prod['code']] = {'tmpl_id': tmpl_id, 'prod_id': prod_id}
    setup_info['products'][prod['code']] = {'tmpl_id': tmpl_id, 'prod_id': prod_id}

# Cancel and delete any old POs for these products to start fresh
old_pos = models.execute_kw(db, uid, password, 'purchase.order', 'search_read',
    [[['partner_id', '=', vendor_id], ['state', 'in', ['draft', 'sent', 'purchase', 'done']]]],
    {'fields': ['id', 'name', 'state']})
for old_po in old_pos:
    try:
        if old_po['state'] in ['draft', 'sent']:
            models.execute_kw(db, uid, password, 'purchase.order', 'button_cancel', [[old_po['id']]])
        print(f"Cancelled old PO: {old_po['name']}")
    except Exception as e:
        print(f"Warning cancelling {old_po['name']}: {e}")

# Create PO lines
po_lines = []
for prod in products_def:
    if prod['code'] not in prod_variant_map:
        continue
    prod_id = prod_variant_map[prod['code']]['prod_id']
    po_lines.append({
        'product_id': prod_id,
        'product_qty': prod['po_qty'],
        'price_unit': prod['cost'],
        'name': prod['name'],
        'product_uom': uom_id,
        'date_planned': '2024-12-01 10:00:00',
    })

# Create and confirm the PO
try:
    po_id = models.execute_kw(db, uid, password, 'purchase.order', 'create', [{
        'partner_id': vendor_id,
        'order_line': [[0, 0, line] for line in po_lines],
        'date_order': '2024-11-25 08:00:00',
        'notes': 'Medical diagnostic supplies — lot tracking required by compliance',
    }])
    print(f"Created PO (id={po_id})")

    # Confirm PO so it's in 'purchase' state (ready to receive)
    models.execute_kw(db, uid, password, 'purchase.order', 'button_confirm', [[po_id]])
    print(f"Confirmed PO — state=purchase, ready for receipt")
    setup_info['po_id'] = po_id

except Exception as e:
    print(f"ERROR creating/confirming PO: {e}", file=sys.stderr)
    sys.exit(1)

with open('/tmp/lot_tracking_receipt_delivery_setup.json', 'w') as f:
    json.dump(setup_info, f, indent=2)
print("Setup complete.")
print(json.dumps(setup_info, indent=2))
PYEOF

if [ $? -ne 0 ]; then
    echo "WARNING: Python setup script had errors — task data may be incomplete"
fi

# Ensure Firefox is running
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8069/web/login > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

for i in $(seq 1 15); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

sleep 2
take_screenshot /tmp/lot_tracking_receipt_delivery_start.png

echo "=== Setup Complete ==="
echo "Vendor: Medline Industries Inc."
echo "Products: LOT-TRACK-001 (tracking=none), LOT-TRACK-002 (tracking=none), LOT-TRACK-003 (tracking=none)"
echo "PO: Confirmed and ready for receipt"
echo "Agent must: (1) enable lot tracking on all 3 products, (2) validate receipt with lot numbers"
