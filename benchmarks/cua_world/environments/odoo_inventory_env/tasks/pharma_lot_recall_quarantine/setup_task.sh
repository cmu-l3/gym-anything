#!/bin/bash
# Setup script for pharma_lot_recall_quarantine task
# Seeds: 3 vendors (one with recall notice), 5 lot-tracked pharma products,
#         10 lots with provenance notes, stock quants in WH/Stock.
# Pre-enables: Storage Locations, Contacts module.

source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"
ODOO_USER="admin"
ODOO_PASS="admin"
RESULT_FILE="/tmp/pharma_recall_result.json"

# --- Detect PostgreSQL container ---
PG_CONTAINER=""
for name in odoo-db odoo-postgres; do
    if docker exec "$name" pg_isready -U odoo 2>/dev/null; then
        PG_CONTAINER="$name"
        break
    fi
done

if [ -z "$PG_CONTAINER" ]; then
    echo "ERROR: No PostgreSQL container found. Trying docker compose..."
    cd /home/ga/odoo
    docker compose up -d 2>/dev/null || true
    sleep 10
    for name in odoo-db odoo-postgres; do
        if docker exec "$name" pg_isready -U odoo 2>/dev/null; then
            PG_CONTAINER="$name"
            break
        fi
    done
fi
echo "PostgreSQL container: ${PG_CONTAINER:-NOT FOUND}"

# --- Delete stale outputs BEFORE recording timestamp ---
rm -f "$RESULT_FILE"

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
    exit 1
fi

# --- Verify database usability ---
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
    sleep 15
fi

# --- Install contacts module via XML-RPC (needed for Contacts app navigation) ---
echo "Installing contacts module via XML-RPC..."
python3 << 'CONTACTS_EOF'
import xmlrpc.client, time

url = 'http://localhost:8069'
db = 'odoo_inventory'

for attempt in range(10):
    try:
        common = xmlrpc.client.ServerProxy(url + '/xmlrpc/2/common', allow_none=True)
        uid = common.authenticate(db, 'admin', 'admin', {})
        if uid:
            break
    except Exception:
        time.sleep(3)

if not uid:
    print("WARNING: Could not authenticate for contacts install")
else:
    models = xmlrpc.client.ServerProxy(url + '/xmlrpc/2/object', allow_none=True)
    mod = models.execute_kw(db, uid, 'admin', 'ir.module.module', 'search_read',
                            [[['name', '=', 'contacts']]], {'fields': ['id', 'state']})
    if mod and mod[0]['state'] != 'installed':
        try:
            models.execute_kw(db, uid, 'admin', 'ir.module.module',
                              'button_immediate_install', [[mod[0]['id']]])
            print("Contacts module installed successfully")
        except Exception as e:
            print("Warning: Contacts install error: {}".format(e))
    else:
        print("Contacts module already installed")
CONTACTS_EOF

# --- Wait for Odoo HTTP readiness ---
for _j in $(seq 1 60); do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${ODOO_URL}/web/login" 2>/dev/null || echo "000")
    [ "$HTTP" = "200" ] && break
    sleep 5
done

echo "Odoo HTTP status: $HTTP"

# --- Seed task data via XML-RPC ---
echo "Setting up pharma recall task data via XMLRPC..."
python3 << 'PYEOF'
import xmlrpc.client
import time
import sys

url = 'http://localhost:8069'
db = 'odoo_inventory'
username = 'admin'
password = 'admin'

# Wait for Odoo XML-RPC readiness
uid = None
for attempt in range(20):
    try:
        common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url), allow_none=True)
        uid = common.authenticate(db, username, password, {})
        if uid:
            break
    except Exception:
        time.sleep(3)

if not uid:
    print("FATAL: Failed to authenticate to Odoo via XML-RPC.")
    sys.exit(1)

models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url), allow_none=True)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs or {})


# ============================================================
# 1. Enable Storage Locations via res.config.settings
# ============================================================
try:
    config_id = execute('res.config.settings', 'create', [{'group_stock_multi_locations': True}])
    execute('res.config.settings', 'execute', [[config_id]])
    print("Storage Locations enabled.")
except Exception as e:
    print("Warning: Could not enable storage locations: {}".format(e))


# ============================================================
# 2. Create Vendors
# ============================================================
def find_or_create_partner(name, extra_vals=None):
    existing = execute('res.partner', 'search_read',
                       [[['name', '=', name]]],
                       {'fields': ['id'], 'limit': 1})
    if existing:
        pid = existing[0]['id']
        if extra_vals:
            execute('res.partner', 'write', [[pid], extra_vals])
        return pid
    vals = {'name': name, 'supplier_rank': 1}
    if extra_vals:
        vals.update(extra_vals)
    return execute('res.partner', 'create', [vals])

RECALL_NOTICE = """FDA REGULATORY ALERT  Ref: FDA-2024-RC-0847

Quality audit failure detected at MedSource Pharma manufacturing facility (Batch Processing Unit 3).

MANDATORY RECALL: All product lots received from MedSource Pharma between January 1, 2024 and February 28, 2024 (inclusive) must be immediately quarantined and segregated from saleable inventory.

Lots received before January 1, 2024 or after February 28, 2024 are NOT affected by this recall.

REPLACEMENT SUPPLIER: Contact SafePharm Industries for emergency replacement orders at existing contract prices.

Regulatory contact: compliance@medsourcepharma.com"""

medsource_id = find_or_create_partner('MedSource Pharma', {'comment': RECALL_NOTICE})
safepharm_id = find_or_create_partner('SafePharm Industries')
biomed_id    = find_or_create_partner('BioMed Supplies Co.')

print("Vendors created: MedSource={}, SafePharm={}, BioMed={}".format(
    medsource_id, safepharm_id, biomed_id))


# ============================================================
# 3. Create Products (all lot-tracked)
# ============================================================
products_spec = [
    {'name': 'Amoxicillin 500mg Capsules',  'default_code': 'PHARMA-AMX'},
    {'name': 'Ibuprofen 400mg Tablets',     'default_code': 'PHARMA-IBU'},
    {'name': 'Cetirizine 10mg Tablets',     'default_code': 'PHARMA-CET'},
    {'name': 'Metformin 850mg Tablets',     'default_code': 'PHARMA-MET'},
    {'name': 'Omeprazole 20mg Capsules',    'default_code': 'PHARMA-OMP'},
]

prod_ids = {}  # default_code -> product.product id
for spec in products_spec:
    code = spec['default_code']
    existing = execute('product.template', 'search_read',
                       [[['default_code', '=', code]]],
                       {'fields': ['id', 'product_variant_ids']})
    if existing:
        execute('product.template', 'write', [[existing[0]['id']],
                {'detailed_type': 'product', 'tracking': 'lot'}])
        prod_ids[code] = existing[0]['product_variant_ids'][0]
    else:
        tmpl_id = execute('product.template', 'create', [{
            'name': spec['name'],
            'default_code': code,
            'detailed_type': 'product',
            'tracking': 'lot',
            'list_price': 25.0,
            'standard_price': 15.0,
        }])
        prod = execute('product.product', 'search_read',
                       [[['product_tmpl_id', '=', tmpl_id]]],
                       {'fields': ['id'], 'limit': 1})
        prod_ids[code] = prod[0]['id']

print("Products created: {}".format(prod_ids))


# ============================================================
# 4. Get WH/Stock location
# ============================================================
wh = execute('stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
stock_loc_id = wh[0]['lot_stock_id'][0]


# ============================================================
# 5. Create Lots with provenance notes
# ============================================================
lots_spec = [
    # (lot_name, product_code, vendor_name, receipt_date, qty, gmp_cert)
    ('AMX-2024-041', 'PHARMA-AMX', 'MedSource Pharma',     '2024-01-15', 500,  'MFG-2024-0041'),
    ('AMX-2024-067', 'PHARMA-AMX', 'SafePharm Industries',  '2024-01-28', 300,  'MFG-2024-0067'),
    ('AMX-2024-089', 'PHARMA-AMX', 'MedSource Pharma',     '2024-02-12', 200,  'MFG-2024-0089'),
    ('IBU-2024-033', 'PHARMA-IBU', 'MedSource Pharma',     '2024-01-22', 800,  'MFG-2024-0033'),
    ('IBU-2024-112', 'PHARMA-IBU', 'MedSource Pharma',     '2024-03-08', 600,  'MFG-2024-0112'),
    ('CET-2024-015', 'PHARMA-CET', 'BioMed Supplies Co.',  '2023-12-20', 1000, 'MFG-2023-0015'),
    ('CET-2024-071', 'PHARMA-CET', 'MedSource Pharma',     '2024-02-18', 500,  'MFG-2024-0071'),
    ('MET-2024-022', 'PHARMA-MET', 'SafePharm Industries',  '2024-01-10', 750,  'MFG-2024-0022'),
    ('MET-2024-045', 'PHARMA-MET', 'SafePharm Industries',  '2024-02-01', 600,  'MFG-2024-0045'),
    ('OMP-2024-019', 'PHARMA-OMP', 'BioMed Supplies Co.',  '2024-01-05', 400,  'MFG-2024-0019'),
]

lot_ids = {}  # lot_name -> stock.lot id

for lot_name, prod_code, vendor, receipt_date, qty, gmp in lots_spec:
    product_id = prod_ids[prod_code]

    note = "Received from {} on {}. GMP Certificate: {}.".format(vendor, receipt_date, gmp)

    existing = execute('stock.lot', 'search_read',
                       [[['name', '=', lot_name], ['product_id', '=', product_id]]],
                       {'fields': ['id']})
    if existing:
        lot_id = existing[0]['id']
        execute('stock.lot', 'write', [[lot_id], {'note': note}])
    else:
        lot_id = execute('stock.lot', 'create', [{
            'name': lot_name,
            'product_id': product_id,
            'note': note,
        }])

    lot_ids[lot_name] = lot_id

    # Set initial stock in WH/Stock for this lot
    # First clear any existing quant for this lot+location
    existing_quants = execute('stock.quant', 'search_read',
                              [[['lot_id', '=', lot_id], ['location_id', '=', stock_loc_id]]],
                              {'fields': ['id']})
    for eq in existing_quants:
        execute('stock.quant', 'write', [[eq['id']], {'inventory_quantity': qty}])
        try:
            execute('stock.quant', 'action_apply_inventory', [[eq['id']]])
        except Exception as e:
            if 'cannot marshal None' in str(e):
                pass  # action succeeded server-side
            else:
                raise

    if not existing_quants:
        quant_id = execute('stock.quant', 'create', [{
            'product_id': product_id,
            'location_id': stock_loc_id,
            'lot_id': lot_id,
            'inventory_quantity': qty,
        }])
        try:
            execute('stock.quant', 'action_apply_inventory', [[quant_id]])
        except Exception as e:
            # action_apply_inventory may return None which Odoo's XML-RPC
            # cannot marshal — the action itself succeeds server-side
            if 'cannot marshal None' in str(e):
                pass  # action succeeded, just can't marshal the response
            else:
                raise

    print("  Lot {} ({}): {} units in WH/Stock".format(lot_name, vendor, qty))

print("All lots and stock created successfully.")
print("Lot IDs: {}".format(lot_ids))
PYEOF

# --- Record task start timestamp (AFTER setup, AFTER deleting stale outputs) ---
date +%s > /tmp/pharma_recall_task_start_timestamp

# --- Launch Firefox to Odoo login page ---
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '${ODOO_URL}/web/login' > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/pharma_recall_initial.png ga

echo "=== pharma_lot_recall_quarantine setup complete ==="
