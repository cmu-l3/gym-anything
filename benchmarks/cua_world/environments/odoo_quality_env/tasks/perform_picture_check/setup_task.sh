#!/bin/bash
echo "=== Setting up perform_picture_check task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Generate the dummy proof image
# We use ImageMagick to create a realistic-looking "photo"
echo "Generating proof image..."
mkdir -p /home/ga/Documents
convert -size 800x600 -background "#E0E0E0" -fill "#333333" -gravity center \
    -pointsize 24 label:"Office Chair - Visual Proof\nDate: $(date +%F)\nBatch: B-2024-QC" \
    /home/ga/Documents/chair_proof.jpg

# Set permissions so the agent user (ga) can read/upload it
chown ga:ga /home/ga/Documents/chair_proof.jpg
chmod 644 /home/ga/Documents/chair_proof.jpg

# 2. Setup Odoo Data (Product, QCP, Check)
echo "Configuring Odoo database..."
python3 << PYTHON_EOF
import xmlrpc.client
import sys
import time

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Get/Create Product "Office Chair"
    prod_ids = models.execute_kw(db, uid, password, 'product.product', 'search', [[['name', '=', 'Office Chair']]])
    if prod_ids:
        pid = prod_ids[0]
    else:
        pid = models.execute_kw(db, uid, password, 'product.product', 'create', [{'name': 'Office Chair', 'type': 'product'}])
        print(f"Created Product: Office Chair (id={pid})")

    # 2. Get/Create Quality Team
    team_ids = models.execute_kw(db, uid, password, 'quality.alert.team', 'search', [[['name', '=', 'Quality Control Team']]])
    if team_ids:
        tid = team_ids[0]
    else:
        tid = models.execute_kw(db, uid, password, 'quality.alert.team', 'create', [{'name': 'Quality Control Team'}])
        print(f"Created Team: Quality Control Team (id={tid})")

    # 3. Create Quality Control Point (Type: Picture)
    # We first search if one exists to avoid duplicates
    qcp_domain = [['product_ids', 'in', [pid]], ['test_type', '=', 'picture'], ['title', '=', 'Chair Visual Inspection']]
    qcp_ids = models.execute_kw(db, uid, password, 'quality.point', 'search', [qcp_domain])
    
    if qcp_ids:
        qcp_id = qcp_ids[0]
        print(f"Found existing QCP (id={qcp_id})")
    else:
        qcp_vals = {
            'title': 'Chair Visual Inspection',
            'product_ids': [(6, 0, [pid])],
            'team_id': tid,
            'test_type': 'picture',
            'note': 'Please upload a photo of the chair condition.',
        }
        qcp_id = models.execute_kw(db, uid, password, 'quality.point', 'create', [qcp_vals])
        print(f"Created QCP: Chair Visual Inspection (id={qcp_id})")

    # 4. Create Quality Check (State: To Do / 'none')
    # We clean up any existing pending checks for this product to ensure a clean state
    pending_checks = models.execute_kw(db, uid, password, 'quality.check', 'search', 
        [[['product_id', '=', pid], ['quality_state', '=', 'none']]])
    if pending_checks:
        models.execute_kw(db, uid, password, 'quality.check', 'unlink', [pending_checks])
        print(f"Cleaned up {len(pending_checks)} pending checks")

    check_vals = {
        'product_id': pid,
        'team_id': tid,
        'point_id': qcp_id,
        'test_type': 'picture',
        'quality_state': 'none', # 'none' = To Do
    }
    check_id = models.execute_kw(db, uid, password, 'quality.check', 'create', [check_vals])
    print(f"Created Quality Check (id={check_id})")
    
    # Save check ID for export script to reference later if needed
    with open('/tmp/target_check_id.txt', 'w') as f:
        f.write(str(check_id))

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# 3. Launch Application
# Navigate directly to Quality Checks list to save agent some navigation time
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#action=quality_control.quality_check_action_main&view_type=list"

# 4. Capture Initial State
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="