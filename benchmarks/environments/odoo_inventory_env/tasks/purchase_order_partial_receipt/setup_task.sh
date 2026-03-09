#!/bin/bash
# Setup script for Purchase Order Partial Receipt task
# Creates 3 vendors and 3 electronic component products
# Clears any old purchase orders for these products

echo "=== Setting up Purchase Order Partial Receipt ==="

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

# Vendors and their info
vendors_def = [
    {
        'name': 'Industrial Supplies Co.',
        'email': 'orders@industrialsupplies.com',
        'phone': '+1-312-555-0101',
        'street': '801 Industrial Pkwy',
        'city': 'Chicago',
        'zip': '60601',
    },
    {
        'name': 'Automation Parts Direct',
        'email': 'sales@automationpartsdirect.com',
        'phone': '+1-513-555-0202',
        'street': '4400 Automation Drive',
        'city': 'Cincinnati',
        'zip': '45201',
    },
    {
        'name': 'Component World',
        'email': 'procurement@componentworld.com',
        'phone': '+1-214-555-0303',
        'street': '9900 Component Blvd',
        'city': 'Dallas',
        'zip': '75201',
    },
]

vendor_ids = {}
for vendor_def in vendors_def:
    existing = models.execute_kw(db, uid, password, 'res.partner', 'search',
        [[['name', '=', vendor_def['name']]]])
    if existing:
        vendor_ids[vendor_def['name']] = existing[0]
        print(f"Found vendor: {vendor_def['name']} (id={existing[0]})")
    else:
        vid = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
            'name': vendor_def['name'],
            'supplier_rank': 1,
            'company_type': 'company',
            'email': vendor_def['email'],
            'phone': vendor_def['phone'],
            'street': vendor_def['street'],
            'city': vendor_def['city'],
            'zip': vendor_def['zip'],
        }])
        vendor_ids[vendor_def['name']] = vid
        print(f"Created vendor: {vendor_def['name']} (id={vid})")

# Products with vendor prices
products_def = [
    {
        'name': 'Parker Hannifin Push-In Fitting 6mm',
        'code': 'ELEC-COMP-001',
        'list_price': 5.99,
        'vendor_prices': {
            'Industrial Supplies Co.': 3.85,
            'Automation Parts Direct': 3.42,
            'Component World': 4.10,
        },
    },
    {
        'name': 'Phoenix Contact UK5-TWIN Terminal Block',
        'code': 'ELEC-COMP-002',
        'list_price': 3.49,
        'vendor_prices': {
            'Industrial Supplies Co.': 2.15,
            'Automation Parts Direct': 1.98,
            'Component World': 1.87,
        },
    },
    {
        'name': 'HellermannTyton T50REC Cable Ties 100-pack',
        'code': 'ELEC-COMP-003',
        'list_price': 11.99,
        'vendor_prices': {
            'Industrial Supplies Co.': 8.20,
            'Automation Parts Direct': 8.65,
            'Component World': 7.95,
        },
    },
]

setup_info = {'vendor_ids': vendor_ids, 'products': {}}

for prod in products_def:
    existing = models.execute_kw(db, uid, password, 'product.template', 'search_read',
        [[['default_code', '=', prod['code']]]], {'fields': ['id']})
    if existing:
        tmpl_id = existing[0]['id']
        # Clear existing vendor pricelists to start fresh
        existing_supplierinfo = models.execute_kw(db, uid, password, 'product.supplierinfo', 'search',
            [[['product_tmpl_id', '=', tmpl_id]]])
        if existing_supplierinfo:
            models.execute_kw(db, uid, password, 'product.supplierinfo', 'unlink',
                [existing_supplierinfo])
            print(f"Cleared old vendor pricelists for {prod['code']}")
    else:
        tmpl_id = models.execute_kw(db, uid, password, 'product.template', 'create', [{
            'name': prod['name'],
            'default_code': prod['code'],
            'detailed_type': 'product',
            'list_price': prod['list_price'],
            'categ_id': categ_id,
            'uom_id': uom_id,
            'uom_po_id': uom_id,
            'sale_ok': True,
            'purchase_ok': True,
        }])
        print(f"Created product: {prod['name']}")

    prod_variant_ids = models.execute_kw(db, uid, password, 'product.product', 'search',
        [[['product_tmpl_id', '=', tmpl_id]]])
    prod_id = prod_variant_ids[0] if prod_variant_ids else None

    # Add vendor pricelists (supplierinfo) for all 3 vendors with their prices
    # This makes the prices visible when creating a PO
    for vendor_name, price in prod['vendor_prices'].items():
        vid = vendor_ids.get(vendor_name)
        if vid:
            try:
                models.execute_kw(db, uid, password, 'product.supplierinfo', 'create', [{
                    'partner_id': vid,
                    'product_tmpl_id': tmpl_id,
                    'price': price,
                    'min_qty': 1.0,
                    'delay': 5,
                }])
            except Exception as e:
                print(f"Warning creating supplierinfo for {vendor_name}/{prod['code']}: {e}")

    setup_info['products'][prod['code']] = {'tmpl_id': tmpl_id, 'prod_id': prod_id}
    print(f"  {prod['code']}: vendor prices set")

# Cancel/delete any existing POs for these products to start clean
all_pos = models.execute_kw(db, uid, password, 'purchase.order', 'search_read',
    [[['state', 'not in', ['cancel']]]],
    {'fields': ['id', 'name', 'state', 'partner_id']})
for po in all_pos:
    # Check if any line is for our products
    lines = models.execute_kw(db, uid, password, 'purchase.order.line', 'search_read',
        [[['order_id', '=', po['id']]]],
        {'fields': ['product_id']})
    prod_ids_in_po = [l['product_id'][0] for l in lines if l.get('product_id')]
    our_prod_ids = [setup_info['products'][code]['prod_id']
                   for code in setup_info['products']
                   if setup_info['products'][code].get('prod_id')]
    if any(pid in our_prod_ids for pid in prod_ids_in_po):
        try:
            if po['state'] in ['draft', 'sent']:
                models.execute_kw(db, uid, password, 'purchase.order', 'button_cancel', [[po['id']]])
                print(f"Cancelled existing PO {po['name']}")
            elif po['state'] == 'purchase':
                # Can't easily cancel confirmed PO, just log
                print(f"Warning: existing confirmed PO {po['name']} for our products — may affect results")
        except Exception as e:
            print(f"Warning cancelling PO {po['name']}: {e}")

with open('/tmp/purchase_order_partial_receipt_setup.json', 'w') as f:
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
take_screenshot /tmp/purchase_order_partial_receipt_start.png

echo "=== Setup Complete ==="
echo "Vendors: Industrial Supplies Co., Automation Parts Direct, Component World"
echo "Products: ELEC-COMP-001, ELEC-COMP-002, ELEC-COMP-003 (with vendor pricelists)"
echo "Agent must: compare prices, create POs with cheapest vendors, process partial receipts"
