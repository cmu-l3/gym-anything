#!/bin/bash
# Setup script for Three-Step Delivery Fulfillment task
# Creates 3 products, a customer, ensures sufficient stock,
# and resets warehouse to 1-step outgoing (agent must configure 3-step)

echo "=== Setting up Three-Step Delivery Fulfillment ==="

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

# Get warehouse and RESET it to 1-step delivery (ship_only)
wh_ids = models.execute_kw(db, uid, password, 'stock.warehouse', 'search_read',
    [[]], {'fields': ['id', 'name', 'delivery_steps'], 'limit': 1})
if not wh_ids:
    print("ERROR: No warehouse found", file=sys.stderr)
    sys.exit(1)
wh_id = wh_ids[0]['id']
current_steps = wh_ids[0].get('delivery_steps', 'ship_only')
print(f"Warehouse '{wh_ids[0]['name']}' (id={wh_id}), current delivery_steps={current_steps}")

# Reset to 1-step (agent must configure 3-step)
try:
    models.execute_kw(db, uid, password, 'stock.warehouse', 'write',
        [[wh_id], {'delivery_steps': 'ship_only'}])
    print("Warehouse reset to 1-step (ship_only)")
except Exception as e:
    print(f"Warning: could not reset warehouse steps: {e}")

# Get or create customer "TechSource Procurement LLC"
cust_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
    [[['name', '=', 'TechSource Procurement LLC']]])
if cust_ids:
    cust_id = cust_ids[0]
    print(f"Found customer TechSource Procurement LLC (id={cust_id})")
else:
    cust_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
        'name': 'TechSource Procurement LLC',
        'customer_rank': 1,
        'company_type': 'company',
        'email': 'purchasing@techsource.com',
        'phone': '+1-415-555-0192',
        'street': '2400 Industrial Blvd',
        'city': 'San Jose',
        'zip': '95131',
    }])
    print(f"Created customer TechSource Procurement LLC (id={cust_id})")

# Real packaging/industrial products
products = [
    {'name': '3M 2050 General Purpose Masking Tape 2in 60yd',      'code': '3STEP-001', 'qty': 100.0, 'price': 8.49,  'cost': 4.50},
    {'name': 'Protective Foam Roll 1/4in x 12in x 10ft',            'code': '3STEP-002', 'qty': 80.0,  'price': 24.99, 'cost': 14.00},
    {'name': 'Scotch 3750 Heavy Duty Packing Tape 2in 60yd',        'code': '3STEP-003', 'qty': 60.0,  'price': 6.99,  'cost': 3.80},
]

setup_info = {'stock_loc_id': stock_loc_id, 'wh_id': wh_id, 'cust_id': cust_id, 'products': {}}

for prod in products:
    existing = models.execute_kw(db, uid, password, 'product.template', 'search_read',
        [[['default_code', '=', prod['code']]]], {'fields': ['id']})
    if existing:
        tmpl_id = existing[0]['id']
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
        }])
        print(f"Created product: {prod['name']}")

    prod_variant_ids = models.execute_kw(db, uid, password, 'product.product', 'search',
        [[['product_tmpl_id', '=', tmpl_id]]])
    prod_id = prod_variant_ids[0] if prod_variant_ids else None
    if not prod_id:
        print(f"ERROR: No variant for {prod['name']}", file=sys.stderr)
        continue

    try:
        models.execute_kw(db, uid, password, 'product.product', 'write',
            [[prod_id], {'standard_price': prod['cost']}])
    except:
        pass

    # Set stock to initial quantity
    quant_ids = models.execute_kw(db, uid, password, 'stock.quant', 'search',
        [[['product_id', '=', prod_id], ['location_id', '=', stock_loc_id]]])
    if quant_ids:
        quant_id = quant_ids[0]
        models.execute_kw(db, uid, password, 'stock.quant', 'write',
            [[quant_id], {'inventory_quantity': prod['qty']}])
    else:
        quant_id = models.execute_kw(db, uid, password, 'stock.quant', 'create', [{
            'product_id': prod_id,
            'location_id': stock_loc_id,
            'inventory_quantity': prod['qty'],
        }])
    try:
        models.execute_kw(db, uid, password, 'stock.quant', 'action_apply_inventory', [[quant_id]])
    except Exception as e:
        print(f"Warning apply_inventory: {e}")
        try:
            models.execute_kw(db, uid, password, 'stock.quant', 'write',
                [[quant_id], {'quantity': prod['qty']}])
        except:
            pass
    print(f"  {prod['code']}: qty={prod['qty']}")
    setup_info['products'][prod['code']] = {'tmpl_id': tmpl_id, 'prod_id': prod_id}

with open('/tmp/three_step_delivery_fulfillment_setup.json', 'w') as f:
    json.dump(setup_info, f, indent=2)
print("Setup complete.")
print(json.dumps(setup_info, indent=2))
PYEOF

if [ $? -ne 0 ]; then
    echo "WARNING: Python setup script had errors — task data may be incomplete"
fi

# Record baseline
INITIAL_PICKING_COUNT=$(odoo_query "SELECT COUNT(*) FROM stock_picking")
INITIAL_SO_COUNT=$(odoo_query "SELECT COUNT(*) FROM sale_order")
echo "$INITIAL_PICKING_COUNT" > /tmp/initial_picking_count
echo "$INITIAL_SO_COUNT" > /tmp/initial_so_count

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
take_screenshot /tmp/three_step_delivery_fulfillment_start.png

echo "=== Setup Complete ==="
echo "Warehouse configured for 1-step (agent must configure 3-step)"
echo "Customer: TechSource Procurement LLC"
echo "Products with stock: 3STEP-001(100), 3STEP-002(80), 3STEP-003(60)"
