#!/bin/bash
echo "=== Exporting result for aviation_altimetry_terrain_clearance ==="

TASK_NAME="aviation_altimetry_terrain_clearance"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'aviation_altimetry_terrain_clearance'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/AviationSafety'
files = {
    'plot': os.path.join(output_dir, 'nh_jan_slp_map.png'),
    'report': os.path.join(output_dir, 'altimetry_hazard_report.txt'),
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
month = ''
system = ''
min_slp = ''
max_error = ''
implication = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if line.startswith('ASSESSMENT_MONTH:'):
                    month = line.split(':', 1)[1].strip()
                elif line.startswith('PRIMARY_HAZARD_SYSTEM:'):
                    system = line.split(':', 1)[1].strip()
                elif line.startswith('MIN_MEAN_SLP_HPA:'):
                    min_slp = line.split(':', 1)[1].strip()
                elif line.startswith('MAX_ALTITUDE_ERROR_FT:'):
                    max_error = line.split(':', 1)[1].strip()
                elif line.startswith('SAFETY_IMPLICATION:'):
                    implication = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['parsed'] = {
    'month': month,
    'system': system,
    'min_slp': min_slp,
    'max_error': max_error,
    'implication': implication
}

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="