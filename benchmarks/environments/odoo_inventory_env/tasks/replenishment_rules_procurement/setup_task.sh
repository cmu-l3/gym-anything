#!/bin/bash
# Setup script for Replenishment Rules Procurement task
# Creates 7 real PPE products: 5 with critically low stock, 2 with adequate stock
# Removes any pre-existing reorder rules for these products

echo "=== Setting up Replenishment Rules Procurement ==="

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
echo "Checking Odoo availability..."
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then echo "Odoo is ready"; break; fi
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

# Base objects
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
    print("ERROR: Could not find WH/Stock location", file=sys.stderr)
    sys.exit(1)

# Get warehouse
wh_ids = models.execute_kw(db, uid, password, 'stock.warehouse', 'search_read',
    [[]], {'fields': ['id', 'name', 'lot_stock_id'], 'limit': 1})
wh_id = wh_ids[0]['id'] if wh_ids else None
print(f"Warehouse ID: {wh_id}, Stock Loc: {stock_loc_id}")

# Get or create a vendor "Grainger Industrial Supply"
vendor_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
    [[['name', '=', 'Grainger Industrial Supply']]])
if vendor_ids:
    vendor_id = vendor_ids[0]
else:
    vendor_id = models.execute_kw(db, uid, password, 'res.partner', 'create', [{
        'name': 'Grainger Industrial Supply',
        'supplier_rank': 1,
        'company_type': 'company',
        'email': 'orders@grainger.com',
        'phone': '+1-800-472-4643',
        'street': '100 Grainger Pkwy',
        'city': 'Lake Forest',
        'zip': '60045',
    }])
print(f"Vendor (Grainger) ID: {vendor_id}")

# 7 real PPE products: 5 low-stock (need rules), 2 adequate-stock (don't need rules)
products = [
    {'name': '3M Hi-Vis Safety Vest Class 2',              'code': 'REPR-001', 'init_qty': 5.0,   'price': 12.99, 'cost': 7.50},
    {'name': 'Pyramex RIDGELINE Hard Hat ANSI Type I',      'code': 'REPR-002', 'init_qty': 0.0,   'price': 16.99, 'cost': 9.00},
    {'name': 'Ansell Edge 82-113 Nitrile Gloves Size M',    'code': 'REPR-003', 'init_qty': 18.0,  'price': 24.99, 'cost': 14.00},
    {'name': 'Ergodyne Skullerz 8985 Safety Glasses',       'code': 'REPR-004', 'init_qty': 2.0,   'price': 9.99,  'cost': 5.50},
    {'name': 'MSA V-Gard 500 Safety Helmet Ventilated',     'code': 'REPR-005', 'init_qty': 8.0,   'price': 32.99, 'cost': 18.00},
    {'name': 'Uvex S2300 Uvextra AFC Safety Spectacles',    'code': 'REPR-006', 'init_qty': 45.0,  'price': 11.99, 'cost': 6.50},
    {'name': '3M 1100 EarSoft Earplugs 200-Pack',          'code': 'REPR-007', 'init_qty': 120.0, 'price': 18.99, 'cost': 10.00},
]

setup_info = {'stock_loc_id': stock_loc_id, 'wh_id': wh_id, 'products': {}}

for prod in products:
    # Get or create product
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
            'purchase_ok': True,
            'sale_ok': True,
        }])
        print(f"Created: {prod['name']}")

    # Get variant
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
        print(f"Warning cost: {e}")

    # Add vendor pricelist
    try:
        existing_si = models.execute_kw(db, uid, password, 'product.supplierinfo', 'search',
            [[['product_tmpl_id', '=', tmpl_id], ['partner_id', '=', vendor_id]]])
        if not existing_si:
            models.execute_kw(db, uid, password, 'product.supplierinfo', 'create', [{
                'partner_id': vendor_id,
                'product_tmpl_id': tmpl_id,
                'price': prod['cost'] * 1.1,
                'min_qty': 1.0,
                'delay': 5,
            }])
    except Exception as e:
        print(f"Warning supplierinfo: {e}")

    # Remove any existing reorder rules for this product
    op_ids = models.execute_kw(db, uid, password, 'stock.warehouse.orderpoint', 'search',
        [[['product_id', '=', prod_id]]])
    if op_ids:
        models.execute_kw(db, uid, password, 'stock.warehouse.orderpoint', 'unlink', [op_ids])
        print(f"  Removed {len(op_ids)} existing reorder rule(s) for {prod['code']}")

    # Set stock quantity
    quant_ids = models.execute_kw(db, uid, password, 'stock.quant', 'search',
        [[['product_id', '=', prod_id], ['location_id', '=', stock_loc_id]]])
    init_qty = prod['init_qty']
    if init_qty > 0:
        if quant_ids:
            quant_id = quant_ids[0]
            models.execute_kw(db, uid, password, 'stock.quant', 'write',
                [[quant_id], {'inventory_quantity': init_qty}])
        else:
            quant_id = models.execute_kw(db, uid, password, 'stock.quant', 'create', [{
                'product_id': prod_id,
                'location_id': stock_loc_id,
                'inventory_quantity': init_qty,
            }])
        try:
            models.execute_kw(db, uid, password, 'stock.quant', 'action_apply_inventory',
                [[quant_id]])
        except Exception as e:
            print(f"  Warning apply_inventory: {e}")
            try:
                models.execute_kw(db, uid, password, 'stock.quant', 'write',
                    [[quant_id], {'quantity': init_qty}])
            except:
                pass
    else:
        # Zero stock
        if quant_ids:
            models.execute_kw(db, uid, password, 'stock.quant', 'write',
                [quant_ids, {'inventory_quantity': 0.0}])
            try:
                models.execute_kw(db, uid, password, 'stock.quant', 'action_apply_inventory',
                    [quant_ids])
            except:
                try:
                    models.execute_kw(db, uid, password, 'stock.quant', 'write',
                        [quant_ids, {'quantity': 0.0}])
                except:
                    pass

    print(f"  {prod['code']}: qty={init_qty}")
    setup_info['products'][prod['code']] = {
        'tmpl_id': tmpl_id, 'prod_id': prod_id, 'init_qty': init_qty
    }

with open('/tmp/replenishment_rules_procurement_setup.json', 'w') as f:
    json.dump(setup_info, f, indent=2)
print("Setup complete.")
PYEOF

if [ $? -ne 0 ]; then
    echo "WARNING: Python setup script had errors — task data may be incomplete"
fi

# Record baseline
INITIAL_RULE_COUNT=$(odoo_query "SELECT COUNT(*) FROM stock_warehouse_orderpoint op JOIN product_product pp ON op.product_id=pp.id JOIN product_template pt ON pp.product_tmpl_id=pt.id WHERE pt.default_code LIKE 'REPR-%'")
INITIAL_PO_COUNT=$(odoo_query "SELECT COUNT(*) FROM purchase_order")
echo "$INITIAL_RULE_COUNT" > /tmp/initial_repr_rule_count
echo "$INITIAL_PO_COUNT" > /tmp/initial_po_count

# Ensure Firefox is running
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8069/odoo/inventory > /tmp/firefox.log 2>&1 &"
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
take_screenshot /tmp/replenishment_rules_procurement_start.png

echo "=== Setup Complete ==="
echo "Products seeded (low stock, no reorder rules): REPR-001(5), REPR-002(0), REPR-003(18), REPR-004(2), REPR-005(8)"
echo "Products seeded (adequate stock, no rules):    REPR-006(45), REPR-007(120)"
echo "Initial rule count for REPR-* products: $INITIAL_RULE_COUNT"
