#!/bin/bash
# Setup script for lot_tracking_expiry_receipt task
# 1. Enables Lot/Serial and Expiration features in settings
# 2. Creates products without tracking
# 3. Creates a confirmed Purchase Order (Receipt ready to process)
# 4. Writes shipment details to Desktop

echo "=== Setting up lot_tracking_expiry_receipt ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Python setup script
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

def get_connection():
    try:
        common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
        uid = common.authenticate(DB, USERNAME, PASSWORD, {})
        models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
        return uid, models
    except Exception as e:
        print(f"Connection error: {e}", file=sys.stderr)
        sys.exit(1)

uid, models = get_connection()

def execute(model, method, *args, **kwargs):
    return models.execute_kw(DB, uid, PASSWORD, model, method, list(args), kwargs or {})

print("Enabling Inventory Features (Lots & Expiration)...")
# We need to enable group_stock_production_lot and group_stock_tracking_lot and module_product_expiry
# In Odoo, this is often done via res.config.settings
# Note: Changing settings can take a moment

settings_vals = {
    'group_stock_production_lot': True,
    'group_stock_tracking_lot': True,
    'module_product_expiry': True,
    'group_stock_tracking_owner': False
}

# Create a new settings record and execute
settings_id = execute('res.config.settings', 'create', settings_vals)
execute('res.config.settings', 'execute', [settings_id])
print("Settings updated.")

# ─── Data Setup ──────────────────────────────────────────────────────────────

VENDOR_NAME = "Mediterranean Provisions Co."
PROD1_NAME = "Organic Whole Wheat Flour 25kg"
PROD2_NAME = "Extra Virgin Olive Oil 5L"

# 1. Create Vendor
vendor_id = execute('res.partner', 'create', {
    'name': VENDOR_NAME,
    'is_company': True,
    'supplier_rank': 1,
    'email': 'logistics@med-provisions.com'
})
print(f"Created Vendor: {VENDOR_NAME}")

# 2. Create Products (Tracking = 'none' initially)
prod1_id = execute('product.product', 'create', {
    'name': PROD1_NAME,
    'type': 'product', # Storable
    'tracking': 'none', # Agent must change this to 'lot'
    'use_expiration_date': True, # Enable expiration field visibility logic (if applicable in version)
    'list_price': 25.0,
    'standard_price': 18.5,
})

prod2_id = execute('product.product', 'create', {
    'name': PROD2_NAME,
    'type': 'product',
    'tracking': 'none', # Agent must change this to 'lot'
    'use_expiration_date': True,
    'list_price': 65.0,
    'standard_price': 42.0,
})
print(f"Created Products: {PROD1_NAME}, {PROD2_NAME}")

# 3. Create Purchase Order
po_id = execute('purchase.order', 'create', {
    'partner_id': vendor_id,
    'date_order': time.strftime('%Y-%m-%d %H:%M:%S'),
})

# Add lines
execute('purchase.order.line', 'create', {
    'order_id': po_id,
    'product_id': prod1_id,
    'product_qty': 50.0,
    'price_unit': 18.50,
})

execute('purchase.order.line', 'create', {
    'order_id': po_id,
    'product_id': prod2_id,
    'product_qty': 30.0,
    'price_unit': 42.00,
})

# Confirm PO (generates picking)
execute('purchase.order', 'button_confirm', [po_id])
print("Purchase Order Confirmed.")

# Get Picking ID
pickings = execute('stock.picking', 'search_read', 
    [['origin', '=', execute('purchase.order', 'read', [po_id], ['name'])[0]['name']]], 
    {'fields': ['id', 'name']})
picking_id = pickings[0]['id']
print(f"Generated Picking: {pickings[0]['name']}")

# Save Setup Data
setup_data = {
    'vendor_id': vendor_id,
    'po_id': po_id,
    'picking_id': picking_id,
    'prod1_id': prod1_id,
    'prod2_id': prod2_id,
    'prod1_name': PROD1_NAME,
    'prod2_name': PROD2_NAME,
    'prod1_expected_lot': 'WF-2024-1547',
    'prod1_expected_expiry': '2025-06-30',
    'prod2_expected_lot': 'OO-2024-0893',
    'prod2_expected_expiry': '2025-12-15'
}

with open('/tmp/lot_tracking_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

PYEOF

# Create Shipment Details File on Desktop
cat > /home/ga/Desktop/shipment_details.txt << 'EOF'
=== INCOMING SHIPMENT MANIFEST ===
Vendor: Mediterranean Provisions Co.
Date: Today

ITEM 1:
Product: Organic Whole Wheat Flour 25kg
Quantity: 50 Units
Lot Number: WF-2024-1547
Expiration Date: 2025-06-30

ITEM 2:
Product: Extra Virgin Olive Oil 5L
Quantity: 30 Units
Lot Number: OO-2024-0893
Expiration Date: 2025-12-15

INSTRUCTIONS:
1. Ensure product tracking is enabled for these items.
2. Enter Lot Numbers and Expiration Dates exactly as shown above.
3. Validate receipt.
EOF
chown ga:ga /home/ga/Desktop/shipment_details.txt

# Launch Firefox
echo "Starting Firefox..."
ODOO_URL="http://localhost:8069/web/login?db=odoo_demo"
su - ga -c "DISPLAY=:1 firefox '$ODOO_URL' > /dev/null 2>&1 &"

# Wait for Firefox
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla\|odoo"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="