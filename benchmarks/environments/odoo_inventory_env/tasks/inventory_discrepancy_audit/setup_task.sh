#!/bin/bash
# Setup script for Inventory Discrepancy Audit task
# Creates 6 real industrial safety products with deliberately incorrect system quantities

echo "=== Setting up Inventory Discrepancy Audit ==="

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
    docker exec odoo-postgres psql -U odoo -d odoo_inventory \
        -c "UPDATE res_users SET login='admin', password='\$pbkdf2-sha512\$25000\$bla' WHERE id=2" 2>/dev/null || true
    docker exec odoo-postgres psql -U odoo -d odoo_inventory \
        -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
    docker restart odoo-web 2>/dev/null || docker-compose -f /home/ga/odoo/docker-compose.yml restart web 2>/dev/null || true
    sleep 20
else
    echo "Database odoo_inventory exists"
fi

# Wait for Odoo HTTP 200
echo "Waiting for Odoo to serve login page..."
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Odoo is ready (HTTP 200)"
        break
    fi
    if [ "$i" = "60" ]; then
        echo "WARNING: Odoo not returning 200 after 300s (HTTP $HTTP_CODE). Proceeding anyway."
    else
        echo "  Waiting... attempt $i/60 (HTTP $HTTP_CODE)"
        sleep 5
    fi
done

# Record timestamp EARLY so verifier can detect agent actions even if setup partly fails
date +%s > /tmp/task_start_timestamp

# Create/reset task products via Odoo XML-RPC
python3 << 'PYEOF'
import xmlrpc.client, sys, json, time

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, 'admin', password, {})
if not uid:
    print("ERROR: Odoo authentication failed", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

# Get base objects
categ_ids = models.execute_kw(db, uid, password, 'product.category', 'search',
    [[['complete_name', '=', 'All']]])
categ_id = categ_ids[0] if categ_ids else 1

uom_ids = models.execute_kw(db, uid, password, 'uom.uom', 'search',
    [[['name', '=', 'Units']]])
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
    print("ERROR: Could not find WH/Stock location", file=sys.stderr)
    sys.exit(1)
print(f"Using WH/Stock location ID: {stock_loc_id}")

# Real industrial safety products with initial (wrong) system quantities
products = [
    {'name': '3M Peltor OX2000 Safety Glasses',      'code': 'INV-AUDIT-001', 'init_qty': 8.0,  'price': 15.99, 'cost': 8.50},
    {'name': 'Milwaukee 2606-20 M18 Drill Driver',    'code': 'INV-AUDIT-002', 'init_qty': 3.0,  'price': 199.99,'cost': 125.00},
    {'name': 'Stanley 33-725 FatMax 25ft Tape',       'code': 'INV-AUDIT-003', 'init_qty': 22.0, 'price': 24.99, 'cost': 14.00},
    {'name': 'Honeywell FAK10-012 First Aid Kit',     'code': 'INV-AUDIT-004', 'init_qty': 15.0, 'price': 45.00, 'cost': 28.00},
    {'name': '3M 8210 N95 Respirator 20-Pack',        'code': 'INV-AUDIT-005', 'init_qty': 33.0, 'price': 24.99, 'cost': 15.00},
    {'name': 'Klein Tools 32500 11-in-1 Screwdriver', 'code': 'INV-AUDIT-006', 'init_qty': 7.0,  'price': 49.99, 'cost': 30.00},
]

setup_info = {'stock_loc_id': stock_loc_id, 'products': {}}

for prod in products:
    # Get or create product template
    existing = models.execute_kw(db, uid, password, 'product.template', 'search_read',
        [[['default_code', '=', prod['code']]]],
        {'fields': ['id', 'name']})
    if existing:
        tmpl_id = existing[0]['id']
        print(f"Found existing: {prod['name']} (tmpl_id={tmpl_id})")
    else:
        tmpl_id = models.execute_kw(db, uid, password, 'product.template', 'create', [{
            'name': prod['name'],
            'default_code': prod['code'],
            'detailed_type': 'product',
            'list_price': prod['price'],
            'categ_id': categ_id,
            'uom_id': uom_id,
            'uom_po_id': uom_id,
            'purchase_ok': True,
            'sale_ok': True,
        }])
        print(f"Created: {prod['name']} (tmpl_id={tmpl_id})")

    # Get product.product variant
    prod_variant_ids = models.execute_kw(db, uid, password, 'product.product', 'search',
        [[['product_tmpl_id', '=', tmpl_id]]])
    if not prod_variant_ids:
        print(f"ERROR: No variant for {prod['name']}", file=sys.stderr)
        continue
    prod_id = prod_variant_ids[0]

    # Set cost
    try:
        models.execute_kw(db, uid, password, 'product.product', 'write',
            [[prod_id], {'standard_price': prod['cost']}])
    except Exception as e:
        print(f"Warning: cost set failed: {e}")

    # Set initial stock quantity via inventory adjustment
    quant_ids = models.execute_kw(db, uid, password, 'stock.quant', 'search',
        [[['product_id', '=', prod_id], ['location_id', '=', stock_loc_id]]])

    target_qty = prod['init_qty']
    if target_qty > 0:
        if quant_ids:
            quant_id = quant_ids[0]
            models.execute_kw(db, uid, password, 'stock.quant', 'write',
                [[quant_id], {'inventory_quantity': target_qty}])
        else:
            quant_id = models.execute_kw(db, uid, password, 'stock.quant', 'create', [{
                'product_id': prod_id,
                'location_id': stock_loc_id,
                'inventory_quantity': target_qty,
            }])
        try:
            models.execute_kw(db, uid, password, 'stock.quant', 'action_apply_inventory',
                [[quant_id]])
            print(f"  Set qty={target_qty} for {prod['code']}")
        except Exception as e:
            print(f"  Warning: action_apply_inventory failed: {e}")
            # Direct write fallback
            try:
                models.execute_kw(db, uid, password, 'stock.quant', 'write',
                    [[quant_id], {'quantity': target_qty, 'reserved_quantity': 0.0}])
                print(f"  Set qty={target_qty} via direct write for {prod['code']}")
            except Exception as e2:
                print(f"  Warning: direct write also failed: {e2}")
    else:
        # Zero out any existing quant
        if quant_ids:
            models.execute_kw(db, uid, password, 'stock.quant', 'write',
                [quant_ids, {'inventory_quantity': 0.0}])
            try:
                models.execute_kw(db, uid, password, 'stock.quant', 'action_apply_inventory',
                    [quant_ids])
            except Exception as e:
                print(f"  Warning zeroing quant: {e}")
                try:
                    models.execute_kw(db, uid, password, 'stock.quant', 'write',
                        [quant_ids, {'quantity': 0.0}])
                except:
                    pass

    setup_info['products'][prod['code']] = {'tmpl_id': tmpl_id, 'prod_id': prod_id, 'init_qty': prod['init_qty']}

with open('/tmp/inventory_discrepancy_audit_setup.json', 'w') as f:
    json.dump(setup_info, f, indent=2)
print("Setup info saved.")
print(json.dumps(setup_info, indent=2))
PYEOF

if [ $? -ne 0 ]; then
    echo "WARNING: Python setup script had errors — task data may be incomplete"
fi

# Record baseline state
echo "Recording baseline state..."
INITIAL_QUANT_COUNT=$(odoo_query "SELECT COUNT(*) FROM stock_quant sq JOIN product_product pp ON sq.product_id=pp.id JOIN product_template pt ON pp.product_tmpl_id=pt.id WHERE pt.default_code LIKE 'INV-AUDIT-%'")
echo "$INITIAL_QUANT_COUNT" > /tmp/initial_audit_quant_count
# (timestamp was already written earlier)

# Ensure Firefox is open at Odoo
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|odoo"; then
    echo "Launching Firefox..."
    su - ga -c "DISPLAY=:1 firefox http://localhost:8069/web/login > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window and maximize
for i in $(seq 1 20); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

sleep 2
take_screenshot /tmp/inventory_discrepancy_audit_start.png

echo "=== Setup Complete ==="
echo "Products created with system quantities:"
echo "  INV-AUDIT-001 (3M OX2000): system=8,  physical=45"
echo "  INV-AUDIT-002 (Milwaukee): system=3,  physical=12"
echo "  INV-AUDIT-003 (Stanley):   system=22, physical=18"
echo "  INV-AUDIT-004 (Honeywell): system=15, physical=0"
echo "  INV-AUDIT-005 (3M 8210):   system=33, physical=50"
echo "  INV-AUDIT-006 (Klein):     system=7,  physical=7 (NO discrepancy)"
