#!/bin/bash
set -e
echo "=== Setting up update_employee_identity task ==="

source /workspace/scripts/task_utils.sh

# 1. Download the profile image (Real data source)
# Using a stable, open-source avatar from Microsoft's Fluent Emoji set
mkdir -p /home/ga/Documents
IMAGE_URL="https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/Technologist/Flat/technologist_flat.png"
wget -q -O /home/ga/Documents/anita_profile.png "$IMAGE_URL"
chown ga:ga /home/ga/Documents/anita_profile.png
chmod 644 /home/ga/Documents/anita_profile.png

echo "Downloaded profile image to /home/ga/Documents/anita_profile.png"

# 2. Reset Employee Data (Clear image and badge) via XML-RPC
# This ensures the agent must actually perform the work
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    # Wait for Odoo to be responsive
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
    
    # Find Anita Oliver
    ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Anita Oliver']]])
    
    if ids:
        # Clear image_1920 and barcode
        models.execute_kw(db, uid, password, 'hr.employee', 'write', [ids, {
            'image_1920': False,
            'barcode': False
        }])
        print(f"Cleared data for Anita Oliver (ID: {ids[0]})")
    else:
        # Create if missing (fallback for robustness)
        print("Employee 'Anita Oliver' not found, creating...")
        new_id = models.execute_kw(db, uid, password, 'hr.employee', 'create', [{
            'name': 'Anita Oliver',
            'work_email': 'anita.oliver@example.com',
            'department_id': 1  # Assign to a default department if possible
        }])
        print(f"Created Anita Oliver (ID: {new_id})")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Launch Firefox and navigate to Employees
# Using ensuring_firefox from task_utils automatically handles login
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# 5. Capture initial state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="