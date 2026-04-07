#!/bin/bash
set -e
echo "=== Setting up upload_employee_documents task ==="

source /workspace/scripts/task_utils.sh

# 1. Create dummy documents for the agent to upload
mkdir -p /home/ga/Documents
echo "Creating dummy documents..."

# Create a dummy JPG (using imagemagick)
convert -size 400x300 xc:lightblue \
    -gravity center -pointsize 24 -annotate 0 "Eli Lambert ID\nID: 998877" \
    /home/ga/Documents/eli_lambert_id.jpg

# Create a dummy PDF (using imagemagick)
convert -size 595x842 xc:white \
    -gravity center -pointsize 24 -annotate 0 "Employment Contract\n\nEmployee: Eli Lambert\nDate: 2023-01-01\n\nSigned: E. Lambert" \
    /home/ga/Documents/eli_lambert_contract.pdf

# Ensure permissions so 'ga' user can read them
chown -R ga:ga /home/ga/Documents
chmod 644 /home/ga/Documents/eli_lambert_id.jpg
chmod 644 /home/ga/Documents/eli_lambert_contract.pdf

# 2. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure Eli Lambert exists (Odoo demo data)
# We verify this silently to ensure the task is solvable
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                            [[['name', '=', 'Eli Lambert']]])
    if not ids:
        print("ERROR: Employee 'Eli Lambert' not found in demo data!", file=sys.stderr)
        # Create him if missing (fallback)
        models.execute_kw(db, uid, 'admin', 'hr.employee', 'create', [{'name': 'Eli Lambert'}])
        print("Created fallback employee 'Eli Lambert'")
    else:
        print(f"Employee 'Eli Lambert' found (id={ids[0]})")
except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# 4. Launch Firefox and login, navigating to Employee list
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="