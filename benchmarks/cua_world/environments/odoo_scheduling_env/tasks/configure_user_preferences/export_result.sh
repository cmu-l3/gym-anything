#!/bin/bash
echo "=== Exporting configure_user_preferences result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the final state of the admin user from the database
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    # Authenticate
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Read final preferences
    user_data = models.execute_kw(db, uid, password, 'res.users', 'read', [[uid]], 
                                {'fields': ['tz', 'notification_type']})
    
    final_state = {
        'tz': user_data[0].get('tz'),
        'notification_type': user_data[0].get('notification_type')
    }
    
    # Read baseline if available
    baseline = {}
    if os.path.exists('/tmp/user_prefs_baseline.json'):
        with open('/tmp/user_prefs_baseline.json', 'r') as f:
            baseline = json.load(f)
            
    # Construct result object
    result = {
        'baseline': baseline,
        'final': final_state,
        'task_timestamp': os.popen('date +%s').read().strip()
    }
    
    # Save to temp file first to ensure atomic write/permissions
    with open('/tmp/result_temp.json', 'w') as f:
        json.dump(result, f)
        
except Exception as e:
    print(f"Export error: {e}", file=sys.stderr)
    # Save partial error result
    with open('/tmp/result_temp.json', 'w') as f:
        json.dump({'error': str(e)}, f)
PYTHON_EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/result_temp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="