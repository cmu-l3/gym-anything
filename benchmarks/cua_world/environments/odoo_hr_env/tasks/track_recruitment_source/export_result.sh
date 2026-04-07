#!/bin/bash
echo "=== Exporting track_recruitment_source result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo database state
echo "Querying Odoo database..."
python3 << PYTHON_EOF > /tmp/odoo_query_result.json
import xmlrpc.client
import json
import sys
import datetime

url = "http://localhost:8069"
db = "odoo_hr"
username = "admin"
password = "admin"

result = {
    "job_exists": False,
    "source_created": False,
    "source_correct_job": False,
    "applicant_created": False,
    "applicant_linked_correctly": False,
    "source_create_date": "",
    "applicant_create_date": "",
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check Job Position
    job_ids = models.execute_kw(db, uid, password, 'hr.job', 'search',
        [[['name', '=', 'Experienced Developer']]])
    
    if job_ids:
        result["job_exists"] = True
        job_id = job_ids[0]

        # 2. Check Recruitment Source (utm.source + hr.recruitment.source)
        # Find the utm.source first
        utm_ids = models.execute_kw(db, uid, password, 'utm.source', 'search',
            [[['name', '=', 'TechCrunch']]])
        
        target_utm_id = None
        if utm_ids:
            target_utm_id = utm_ids[0]
            
            # Check for link to job in hr.recruitment.source
            rec_source_ids = models.execute_kw(db, uid, password, 'hr.recruitment.source', 'search_read',
                [[['source_id', '=', target_utm_id], ['job_id', '=', job_id]]],
                {'fields': ['create_date']})
            
            if rec_source_ids:
                result["source_created"] = True
                result["source_correct_job"] = True
                result["source_create_date"] = rec_source_ids[0]['create_date']

        # 3. Check Applicant
        # Search by partner_name or name (Subject)
        applicant_domain = ['|', ['partner_name', 'ilike', 'Jane Tech'], ['name', 'ilike', 'Jane Tech']]
        applicant_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search_read',
            [applicant_domain],
            {'fields': ['source_id', 'job_id', 'create_date']})
        
        if applicant_ids:
            # Sort by create_date desc to get latest
            applicant = sorted(applicant_ids, key=lambda x: x['id'], reverse=True)[0]
            result["applicant_created"] = True
            result["applicant_create_date"] = applicant['create_date']
            
            # Check linkage
            # applicant['source_id'] is [id, name] or False
            app_source = applicant.get('source_id')
            if app_source and target_utm_id and app_source[0] == target_utm_id:
                result["applicant_linked_correctly"] = True
            
            # Verify job just in case
            app_job = applicant.get('job_id')
            if app_job and app_job[0] != job_id:
                # If job doesn't match, we might discount points in verification
                pass

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYTHON_EOF

# Combine info into final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
QUERY_RESULT=$(cat /tmp/odoo_query_result.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odoo_state": $QUERY_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"
rm -f /tmp/odoo_query_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="