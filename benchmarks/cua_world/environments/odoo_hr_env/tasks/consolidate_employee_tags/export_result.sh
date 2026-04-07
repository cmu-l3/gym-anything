#!/bin/bash
echo "=== Exporting Consolidate Tags Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_IDS=$(cat /tmp/target_employee_ids.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query current state via Python
python3 << PYTHON_EOF
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "consultant_tag_count": -1,
    "contractor_tag_exists": False,
    "targets_processed": [],
    "targets_correct": 0,
    "total_targets": 0,
    "system_clean": False
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check if 'Contractor' tag exists
    contractor_ids = models.execute_kw(db, uid, password, 'hr.employee.category', 'search', [[['name', '=', 'Contractor']]])
    result['contractor_tag_exists'] = bool(contractor_ids)
    contractor_id = contractor_ids[0] if contractor_ids else None

    # 2. Check if 'Consultant' tag still has employees
    # Note: The agent might have renamed 'Consultant' to 'Contractor', which is a valid solution.
    # If they renamed it, 'Consultant' tag search will fail or return 0 employees if they created a new one.
    
    consultant_ids = models.execute_kw(db, uid, password, 'hr.employee.category', 'search', [[['name', '=', 'Consultant']]])
    
    if consultant_ids:
        # If tag exists, count employees linked to it
        consultant_id = consultant_ids[0]
        emp_with_consultant = models.execute_kw(db, uid, password, 'hr.employee', 'search_count', [[['category_ids', 'in', [consultant_id]]]])
        result['consultant_tag_count'] = emp_with_consultant
    else:
        # Tag deleted or renamed
        result['consultant_tag_count'] = 0

    # 3. Verify specific targets
    target_ids_str = "$TARGET_IDS"
    if target_ids_str:
        target_ids = [int(x) for x in target_ids_str.split(',') if x]
        result['total_targets'] = len(target_ids)
        
        for emp_id in target_ids:
            emp = models.execute_kw(db, uid, password, 'hr.employee', 'read', [emp_id], {'fields': ['name', 'category_ids']})[0]
            tags = emp['category_ids'] # List of IDs
            
            has_contractor = False
            if contractor_id and contractor_id in tags:
                has_contractor = True
                
            has_consultant = False
            if consultant_ids and consultant_ids[0] in tags:
                has_consultant = True
            
            # Check correctness: Must have Contractor AND NOT Consultant
            is_correct = has_contractor and not has_consultant
            if is_correct:
                result['targets_correct'] += 1
                
            result['targets_processed'].append({
                "id": emp_id,
                "name": emp['name'],
                "has_contractor": has_contractor,
                "has_consultant": has_consultant,
                "is_correct": is_correct
            })

    # 4. System clean check
    # Success if consultant_tag_count is 0 AND targets are correct
    if result['consultant_tag_count'] == 0 and result['targets_correct'] == result['total_targets']:
        result['system_clean'] = True

except Exception as e:
    print(f"Error querying Odoo: {e}", file=sys.stderr)
    result['error'] = str(e)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="