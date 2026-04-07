#!/bin/bash
# Setup script for product_variant_configuration
# Enables product variants and prepares the environment

echo "=== Setting up product_variant_configuration ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    if curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null; then
        echo "Odoo XML-RPC ready"
        break
    fi
    sleep 2
done

# 3. Enable 'Product Variants' setting via Python/XML-RPC
# This is critical: if this setting is off, the "Attributes" tab is hidden
python3 << 'PYEOF'
import xmlrpc.client
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

    # Enable group_product_variant
    # In Odoo, we typically set this by writing to res.config.settings
    # or ensuring the group is active. A reliable way in demo data is ensuring
    # the user has the group 'product.group_product_variant'
    
    # 1. Activate the group globally (often implied by installing Sales/Inventory, 
    # but we ensure it's enabled in settings)
    models.execute_kw(DB, uid, PASSWORD, 'res.config.settings', 'create', [{
        'group_product_variant': True
    }])
    
    # 2. Also execute the 'execute' method on the settings to apply it
    # Note: creating res.config.settings automatically applies in recent Odoo versions,
    # but explicitly calling execute is safer
    settings_id = models.execute_kw(DB, uid, PASSWORD, 'res.config.settings', 'create', [{'group_product_variant': True}])
    models.execute_kw(DB, uid, PASSWORD, 'res.config.settings', 'execute', [[settings_id]])

    print("Product Variants setting enabled.")

    # Record initial product count
    count = models.execute_kw(DB, uid, PASSWORD, 'product.template', 'search_count', [[]])
    with open('/tmp/initial_product_count.txt', 'w') as f:
        f.write(str(count))

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
PYEOF

# 4. Ensure Firefox is running and focused
echo "Ensuring Firefox is running..."
ODOO_URL="http://localhost:8069/web/login?db=odoo_demo"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$ODOO_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 5. Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="