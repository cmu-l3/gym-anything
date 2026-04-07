#!/bin/bash
echo "=== Exporting result for siberian_ice_road_logistics ==="

TASK_NAME="siberian_ice_road_logistics"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'siberian_ice_road_logistics'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/IceRoads'
files = {
    'map_plot': os.path.join(output_dir, 'yakutia_jan_map.png'),
    'line_plot': os.path.join(output_dir, 'yakutsk_annual_profile.png'),
    'report': os.path.join(output_dir, 'safe_transit_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Parse report fields
report_path = files['report']
location = ''
threshold_k = ''
safe_months = ''
jan_min_temp_k = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('LOCATION:'):
                location = line.split(':', 1)[1].strip()
            elif line.startswith('THRESHOLD_K:'):
                threshold_k = line.split(':', 1)[1].strip()
            elif line.startswith('SAFE_MONTHS:'):
                safe_months = line.split(':', 1)[1].strip()
            elif line.startswith('JAN_MIN_TEMP_K:'):
                jan_min_temp_k = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['location'] = location
result['threshold_k'] = threshold_k
result['safe_months'] = safe_months
result['jan_min_temp_k'] = jan_min_temp_k

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="