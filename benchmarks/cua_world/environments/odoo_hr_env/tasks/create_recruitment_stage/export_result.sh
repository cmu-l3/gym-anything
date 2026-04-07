#!/bin/bash
echo "=== Exporting create_recruitment_stage results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Python script to verify database state and export results
# We use Python here because XML-RPC manipulation in bash is painful
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result_data = {
    "task_passed": False,
    "error": None,
    "stage_found": False,
    "name_correct": False,
    "description_correct": False,
    "sequence_correct": False,
    "count_increased": False,
    "details": {}
}

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # --- Criterion 1: Check if stage exists ---
    # We search case-insensitive for robustness, but score based on exact match later
    target_stages = models.execute_kw(db, uid, 'admin', 'hr.recruitment.stage', 'search_read',
                                     [[['name', 'ilike', 'Technical Assessment']]],
                                     {'fields': ['id', 'name', 'sequence', 'requirements']})
    
    if target_stages:
        result_data["stage_found"] = True
        stage = target_stages[0] # Take the first match
        result_data["details"]["found_stage"] = stage
        
        # --- Criterion 2: Name Exact Match ---
        if stage['name'] == 'Technical Assessment':
            result_data["name_correct"] = True
            
        # --- Criterion 3: Description/Requirements ---
        # Must contain "technical evaluation" (case insensitive)
        reqs = stage.get('requirements', '')
        if reqs and 'technical evaluation' in str(reqs).lower():
            result_data["description_correct"] = True
        result_data["details"]["actual_requirements"] = reqs
        
        # --- Criterion 4: Sequence / Ordering ---
        # Get sequences of reference stages
        refs = models.execute_kw(db, uid, 'admin', 'hr.recruitment.stage', 'search_read',
                                [[['name', 'in', ['First Interview', 'Second Interview']]]],
                                {'fields': ['name', 'sequence']})
        
        seq_map = {r['name']: r['sequence'] for r in refs}
        my_seq = stage['sequence']
        
        first_seq = seq_map.get('First Interview', -1)
        second_seq = seq_map.get('Second Interview', 9999)
        
        # Logic: First < My <= Second
        # Note: In Odoo, if you drag it between them, it might share a sequence or be in between.
        # The most important thing is it's strictly greater than First Interview
        # and strictly less than Second Interview (if sequences differ), 
        # OR if sequences are equal, Odoo orders by ID. 
        # Simplified check: strictly greater than First, less than or equal to Second.
        
        if first_seq < my_seq and my_seq <= second_seq:
            result_data["sequence_correct"] = True
            
        result_data["details"]["sequences"] = {
            "First Interview": first_seq,
            "Technical Assessment": my_seq,
            "Second Interview": second_seq
        }

    # --- Criterion 5: Count Check ---
    # Load initial count
    initial_count = 0
    if os.path.exists('/tmp/initial_state.json'):
        with open('/tmp/initial_state.json', 'r') as f:
            initial_data = json.load(f)
            initial_count = initial_data.get('count', 0)
            
    final_count = models.execute_kw(db, uid, 'admin', 'hr.recruitment.stage', 'search_count', [[]])
    
    if final_count == initial_count + 1:
        result_data["count_increased"] = True
        
    result_data["details"]["counts"] = {
        "initial": initial_count,
        "final": final_count
    }

except Exception as e:
    result_data["error"] = str(e)

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result_data, f, indent=2)

print("Export complete. Result data:")
print(json.dumps(result_data, indent=2))
PYEOF

# Fix permissions so ga user can read it (if ran as root)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export script finished ==="