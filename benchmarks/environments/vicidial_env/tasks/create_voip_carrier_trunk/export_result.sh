#!/bin/bash
set -e
echo "=== Exporting create_voip_carrier_trunk results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Gather data for verification using Python for robust JSON handling
# We use Python inside the container logic via docker exec if needed, 
# but here we run python on the host (VM) which connects to docker mysql.

python3 -c "
import json
import subprocess
import time
import os

def run_query(query):
    cmd = ['docker', 'exec', 'vicidial', 'mysql', '-ucron', '-p1234', '-D', 'asterisk', '-N', '-e', query]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return result
    except subprocess.CalledProcessError:
        return None

def get_row_as_dict(carrier_id):
    # Get columns first
    cols_cmd = ['docker', 'exec', 'vicidial', 'mysql', '-ucron', '-p1234', '-D', 'asterisk', '-N', '-e', 
                f\"SELECT column_name FROM information_schema.columns WHERE table_schema='asterisk' AND table_name='vicidial_server_carriers'\"]
    try:
        cols = subprocess.check_output(cols_cmd).decode('utf-8').strip().split('\n')
    except:
        return None
    
    # Get values
    # We use a separator that is unlikely to be in the data '|||'
    query = f\"SELECT {','.join(cols)} FROM vicidial_server_carriers WHERE carrier_id='{carrier_id}'\"
    # MySQL output with -B is tab separated, but fields like dialplan might contain tabs/newlines. 
    # Safest is to fetch specific fields we care about individually or use a Python driver (not available here).
    # Let's fetch the key fields individually to ensure safety.
    
    data = {}
    fields = ['carrier_id', 'carrier_name', 'registration_string', 'account_entry', 'protocol', 'server_ip', 'dialplan_entry', 'active']
    
    found = False
    for f in fields:
        val = run_query(f\"SELECT {f} FROM vicidial_server_carriers WHERE carrier_id='{carrier_id}'\")
        if val is not None:
            found = True
            data[f] = val
        else:
            data[f] = None
            
    return data if found else None

# 1. Get Task Metadata
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
except:
    start_time = 0

try:
    with open('/tmp/vicidial_active_server_ip.txt', 'r') as f:
        active_server_ip = f.read().strip()
except:
    active_server_ip = ''
    
try:
    with open('/tmp/initial_carrier_count.txt', 'r') as f:
        initial_count = int(f.read().strip())
except:
    initial_count = 0

# 2. Query Current State
current_count_str = run_query(\"SELECT COUNT(*) FROM vicidial_server_carriers\")
current_count = int(current_count_str) if current_count_str else 0

carrier_data = get_row_as_dict('FLOWRT01')

# 3. Check for Anti-Gaming (Timestamp check isn't easily possible on DB rows here without 'entry_date' field logic, 
# but we check count increase)
    
result = {
    'task_start_time': start_time,
    'export_time': int(time.time()),
    'initial_count': initial_count,
    'current_count': current_count,
    'carrier_found': carrier_data is not None,
    'carrier_data': carrier_data,
    'active_server_ip': active_server_ip,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Export successful.')
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="