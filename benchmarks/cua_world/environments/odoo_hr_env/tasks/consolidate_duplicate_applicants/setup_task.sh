#!/bin/bash
set -e
echo "=== Setting up Consolidate Duplicate Applicants task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create data via Python XML-RPC
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import datetime
import time

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Ensure Job Position exists
    job_name = "Senior Developer"
    job_ids = models.execute_kw(db, uid, password, 'hr.job', 'search', [[['name', '=', job_name]]])
    if not job_ids:
        job_id = models.execute_kw(db, uid, password, 'hr.job', 'create', [{'name': job_name}])
        print(f"Created Job: {job_name}")
    else:
        job_id = job_ids[0]

    # 2. Ensure 'Refused' stage exists
    stage_ids = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'search', [[['name', '=', 'Refused']]])
    if not stage_ids:
        refused_stage_id = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'create', [{
            'name': 'Refused',
            'sequence': 100,
            'fold': True
        }])
        print("Created 'Refused' stage")
    else:
        refused_stage_id = stage_ids[0]

    # 3. Find 'New' stage
    new_stage_ids = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'search', [[['name', '=', 'New']]])
    if new_stage_ids:
        new_stage_id = new_stage_ids[0]
    else:
        # Fallback if "New" doesn't exist (unlikely in demo data)
        new_stage_id = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'create', [{'name': 'New', 'sequence': 1}])

    # 4. Clean up existing Sarah Connor applications to ensure clean state
    existing_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search', [[['partner_name', '=', 'Sarah Connor']]])
    if existing_ids:
        models.execute_kw(db, uid, password, 'hr.applicant', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing applications")

    # 5. Create OLD application (Refused)
    old_app_id = models.execute_kw(db, uid, password, 'hr.applicant', 'create', [{
        'name': 'Senior Developer - Sarah Connor',
        'partner_name': 'Sarah Connor',
        'job_id': job_id,
        'stage_id': refused_stage_id,
        'description': 'Old application from 6 months ago.',
        'active': True  # Important: It starts active, agent must archive it
    }])
    
    # Add the critical note to the old application
    models.execute_kw(db, uid, password, 'hr.applicant', 'message_post', [old_app_id], {
        'body': 'Interview feedback: Candidate is strong technically but requires <b>visa sponsorship</b>.',
        'message_type': 'comment',
        'subtype_xmlid': 'mail.mt_note'
    })
    print(f"Created OLD application (ID: {old_app_id}) with visa note")

    # Write ID to temp file for verification later
    with open('/tmp/old_app_id.txt', 'w') as f:
        f.write(str(old_app_id))

    # 6. Create NEW application (New)
    new_app_id = models.execute_kw(db, uid, password, 'hr.applicant', 'create', [{
        'name': 'Senior Developer - Sarah Connor',
        'partner_name': 'Sarah Connor',
        'job_id': job_id,
        'stage_id': new_stage_id,
        'description': 'New application received today.',
        'active': True
    }])
    print(f"Created NEW application (ID: {new_app_id})")
    
    with open('/tmp/new_app_id.txt', 'w') as f:
        f.write(str(new_app_id))

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Launch Firefox to the Recruitment Kanban view
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job_applications"
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="