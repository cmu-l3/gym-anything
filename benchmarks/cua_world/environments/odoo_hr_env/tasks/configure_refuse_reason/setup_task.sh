#!/bin/bash
set -e
echo "=== Setting up task: configure_refuse_reason ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Setup data: Clean existing reason, ensure applicant exists
python3 << 'PYEOF'
import xmlrpc.client
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Archive/Delete any existing "Overqualified" refuse reasons
    # We search case-insensitive to ensure a clean slate
    existing_reasons = models.execute_kw(db, uid, password, 'hr.applicant.refuse.reason', 'search',
        [[['name', 'ilike', 'Overqualified']]])
    
    if existing_reasons:
        print(f"Cleaning up {len(existing_reasons)} existing 'Overqualified' reasons...")
        try:
            models.execute_kw(db, uid, password, 'hr.applicant.refuse.reason', 'unlink', [existing_reasons])
        except Exception as e:
            # If unlink fails (e.g. referenced elsewhere), try renaming/archiving
            print(f"Could not unlink, renaming instead: {e}")
            models.execute_kw(db, uid, password, 'hr.applicant.refuse.reason', 'write',
                [existing_reasons, {'name': 'OLD_Overqualified_' + str(datetime.datetime.now()), 'active': False}])

    # 2. Setup Applicant "Sarah Jenkins"
    # Find "Experienced Developer" job
    job_ids = models.execute_kw(db, uid, password, 'hr.job', 'search',
        [[['name', '=', 'Experienced Developer']]])
    job_id = job_ids[0] if job_ids else False
    
    if not job_id:
        # Create job if missing (unlikely in this env, but safe)
        job_id = models.execute_kw(db, uid, password, 'hr.job', 'create', [{'name': 'Experienced Developer'}])

    # Find "New" stage
    stage_ids = models.execute_kw(db, uid, password, 'hr.recruitment.stage', 'search',
        [[['job_ids', 'in', [job_id]]]], {'limit': 1})
    stage_id = stage_ids[0] if stage_ids else False

    # Check if Sarah exists
    sarah_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search',
        [[['partner_name', '=', 'Sarah Jenkins']]])
    
    if sarah_ids:
        # Reset Sarah to clean state
        print("Resetting existing applicant Sarah Jenkins...")
        models.execute_kw(db, uid, password, 'hr.applicant', 'write',
            [sarah_ids, {
                'active': True,
                'refuse_reason_id': False,
                'stage_id': stage_id,
                'date_closed': False,
                'job_id': job_id
            }])
    else:
        # Create Sarah
        print("Creating new applicant Sarah Jenkins...")
        vals = {
            'name': 'Sarah Jenkins - Experienced Developer',
            'partner_name': 'Sarah Jenkins',
            'email_from': 'sarah.jenkins@example.com',
            'job_id': job_id,
            'stage_id': stage_id,
            'description': 'Experienced Python developer with 5 years experience.'
        }
        models.execute_kw(db, uid, password, 'hr.applicant', 'create', [vals])

    print("Setup complete.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Ensure Firefox is open and on the Recruitment dashboard
# Note: We force a reload to ensure the UI reflects the database state
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job"

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png