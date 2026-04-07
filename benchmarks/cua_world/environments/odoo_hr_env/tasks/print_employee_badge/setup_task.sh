#!/bin/bash
set -e
echo "=== Setting up print_employee_badge task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/badge.pdf
rm -f /home/ga/Downloads/*badge*.pdf 2>/dev/null || true
rm -f /tmp/badge_artifact.pdf 2>/dev/null || true

# Ensure Employee "Anita Oliver" exists
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    if not uid:
        print("Auth failed", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Search for Anita Oliver
    ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                            [[['name', '=', 'Anita Oliver']]])
    
    if not ids:
        print("Creating employee 'Anita Oliver'...")
        models.execute_kw(db, uid, 'admin', 'hr.employee', 'create', [{
            'name': 'Anita Oliver',
            'work_email': 'anita.oliver@example.com',
            'job_title': 'Logistics Manager'
        }])
    else:
        print("Employee 'Anita Oliver' already exists.")

except Exception as e:
    print(f"Error setting up data: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is ready and navigated to Employees
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="