#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/task_final.png

# Kill OpenVSP to release file locks
kill_openvsp

# Generate JSON result with Python
python3 << 'PYEOF'
import json, os

def find_file(filename):
    search_dirs = ['/home/ga/Documents/OpenVSP', '/home/ga/Desktop', '/home/ga/Documents', '/home/ga']
    for d in search_dirs:
        for root, dirs, files in os.walk(d):
            if filename in files:
                return os.path.join(root, filename)
    return None

takeoff_path = find_file('vswing_takeoff.vsp3')
dash_path = find_file('vswing_dash.vsp3')
report_path = find_file('sweep_area_report.txt')

result = {}

def get_file_info(path):
    if path and os.path.isfile(path):
        mtime = int(os.path.getmtime(path))
        try:
            with open(path, 'r', errors='replace') as f:
                content = f.read()
            return {'exists': True, 'mtime': mtime, 'content': content}
        except:
            return {'exists': True, 'mtime': mtime, 'content': ""}
    return {'exists': False, 'mtime': 0, 'content': ""}

result['takeoff'] = get_file_info(takeoff_path)
result['dash'] = get_file_info(dash_path)
result['report'] = get_file_info(report_path)

# Capture DegenGeom CSV contents to ensure they ran it
csvs = {}
for d in ['/home/ga/Documents/OpenVSP', '/home/ga/Documents/OpenVSP/exports']:
    if os.path.exists(d):
        for f in os.listdir(d):
            if f.endswith('.csv'):
                try:
                    with open(os.path.join(d, f), 'r', errors='replace') as fp:
                        csvs[f] = fp.read(10000) # read up to 10KB
                except:
                    pass
result['csvs'] = csvs

# Check timestamps vs start
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
    result['task_start'] = task_start
except:
    result['task_start'] = 0

# Write result safely
temp_file = '/tmp/temp_result.json'
with open(temp_file, 'w') as f:
    json.dump(result, f)
os.system(f'mv {temp_file} /tmp/task_result.json')
os.system('chmod 666 /tmp/task_result.json')
PYEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="