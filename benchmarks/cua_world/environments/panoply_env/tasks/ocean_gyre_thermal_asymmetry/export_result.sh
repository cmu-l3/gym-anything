#!/bin/bash
echo "=== Exporting result for ocean_gyre_thermal_asymmetry ==="

TASK_NAME="ocean_gyre_thermal_asymmetry"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time, re

task_name = 'ocean_gyre_thermal_asymmetry'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/GyreStudy'
files = {
    'map_plot': os.path.join(output_dir, 'north_atlantic_feb.png'),
    'report': os.path.join(output_dir, 'thermal_asymmetry_report.txt'),
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
report_data = {
    'sub_west': '',
    'sub_east': '',
    'mid_west': '',
    'mid_east': '',
    'sub_logic': '',
    'mid_logic': ''
}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
            
        for line in content.splitlines():
            line = line.strip()
            # Extract numbers (including negatives and decimals) using regex for temps
            if line.startswith('SUB_WEST_30N_78W_C:'):
                match = re.search(r'[-+]?\d*\.\d+|\d+', line.split(':', 1)[1])
                report_data['sub_west'] = match.group() if match else ''
            elif line.startswith('SUB_EAST_30N_12W_C:'):
                match = re.search(r'[-+]?\d*\.\d+|\d+', line.split(':', 1)[1])
                report_data['sub_east'] = match.group() if match else ''
            elif line.startswith('MID_WEST_45N_60W_C:'):
                match = re.search(r'[-+]?\d*\.\d+|\d+', line.split(':', 1)[1])
                report_data['mid_west'] = match.group() if match else ''
            elif line.startswith('MID_EAST_45N_12W_C:'):
                match = re.search(r'[-+]?\d*\.\d+|\d+', line.split(':', 1)[1])
                report_data['mid_east'] = match.group() if match else ''
            # Exact string logic for the sides
            elif line.startswith('SUBTROPICAL_WARMER_SIDE:'):
                report_data['sub_logic'] = line.split(':', 1)[1].strip().upper()
            elif line.startswith('MIDLATITUDE_WARMER_SIDE:'):
                report_data['mid_logic'] = line.split(':', 1)[1].strip().upper()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result.update(report_data)

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="