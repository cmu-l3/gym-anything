#!/bin/bash
set -e
echo "=== Setting up import_employees_csv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare CSV file
mkdir -p /home/ga/Documents
CSV_FILE="/home/ga/Documents/new_hires.csv"

cat > "$CSV_FILE" << EOF
Employee Name,Work Email,Work Phone,Department,Job Title
Sandra Mitchell,sandra.mitchell@yourcompany.com,+1 555-0191,Sales,Account Executive
Kevin Torres,kevin.torres@yourcompany.com,+1 555-0192,Administration,Office Coordinator
Laura Chen,laura.chen@yourcompany.com,+1 555-0193,Research & Development,Software Engineer
Marcus Johnson,marcus.johnson@yourcompany.com,+1 555-0194,Professional Services,Implementation Consultant
Diana Ramirez,diana.ramirez@yourcompany.com,+1 555-0195,Sales,Sales Representative
EOF

chown ga:ga "$CSV_FILE"
echo "Created CSV file at $CSV_FILE"

# 2. Record initial employee count and clean up any previous run artifacts
# We use python/xmlrpc to communicate with Odoo
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Auth failed", file=sys.stderr)
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Optional: Clean up these specific employees if they exist from a previous failed run
    # so the agent starts clean.
    target_emails = [
        "sandra.mitchell@yourcompany.com",
        "kevin.torres@yourcompany.com",
        "laura.chen@yourcompany.com",
        "marcus.johnson@yourcompany.com",
        "diana.ramirez@yourcompany.com"
    ]
    
    existing_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
        [[['work_email', 'in', target_emails]]])
        
    if existing_ids:
        print(f"Cleaning up {len(existing_ids)} existing records from previous runs...")
        models.execute_kw(db, uid, password, 'hr.employee', 'unlink', [existing_ids])

    # Record initial count
    count = models.execute_kw(db, uid, password, 'hr.employee', 'search_count', [[]])
    with open('/tmp/initial_employee_count.txt', 'w') as f:
        f.write(str(count))
    print(f"Initial employee count: {count}")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    # Default to 0 if we can't connect, though this usually implies Odoo isn't ready
    with open('/tmp/initial_employee_count.txt', 'w') as f:
        f.write("0")
PYTHON_EOF

# 3. Open Firefox to the Employees page
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="