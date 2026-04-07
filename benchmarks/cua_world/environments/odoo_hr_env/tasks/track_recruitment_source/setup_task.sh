#!/bin/bash
set -e
echo "=== Setting up track_recruitment_source task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean up any existing data to ensure a fresh start
echo "Cleaning up existing records..."
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoo_hr"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Delete Applicant 'Jane Tech'
    applicant_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search',
        [[['partner_name', 'ilike', 'Jane Tech']]])
    if applicant_ids:
        models.execute_kw(db, uid, password, 'hr.applicant', 'unlink', [applicant_ids])
        print(f"Removed {len(applicant_ids)} existing applicants.")

    # 2. Delete Recruitment Source 'TechCrunch'
    # 'hr.recruitment.source' links a 'utm.source' to a 'hr.job'.
    # We first find the utm.source named 'TechCrunch'.
    utm_ids = models.execute_kw(db, uid, password, 'utm.source', 'search',
        [[['name', '=', 'TechCrunch']]])
    
    if utm_ids:
        # Find hr.recruitment.source records linked to these utm.sources
        rec_source_ids = models.execute_kw(db, uid, password, 'hr.recruitment.source', 'search',
            [[['source_id', 'in', utm_ids]]])
        
        if rec_source_ids:
            models.execute_kw(db, uid, password, 'hr.recruitment.source', 'unlink', [rec_source_ids])
            print(f"Removed {len(rec_source_ids)} recruitment source links.")
        
        # Also clean up the utm.source to be thorough
        models.execute_kw(db, uid, password, 'utm.source', 'unlink', [utm_ids])
        print("Removed underlying utm.source records.")

except Exception as e:
    print(f"Setup cleanup error: {e}", file=sys.stderr)
PYTHON_EOF

# Launch Firefox and navigate to Recruitment app main dashboard
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="