#!/bin/bash
echo "=== Exporting result for himalayan_rotorcraft_rescue_pressure ==="

TASK_NAME="himalayan_rotorcraft_rescue_pressure"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Check if Panoply is still running
APP_RUNNING=$(pgrep -f "Panoply.jar" > /dev/null && echo "true" || echo "false")

python3 << 'PYEOF'
import json, os, time

task_name = 'himalayan_rotorcraft_rescue_pressure'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/HeliSAR'
files = {
    'map': os.path.join(output_dir, 'himalayan_surface_pressure_may.png'),
    'report': os.path.join(output_dir, 'pressure_baseline_report.txt'),
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
target_month = ''
dataset_used = ''
himalayan_pressure = ''
sea_level_diff = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('TARGET_MONTH:'):
                target_month = line.split(':', 1)[1].strip()
            elif line.startswith('DATASET_USED:'):
                dataset_used = line.split(':', 1)[1].strip()
            elif line.startswith('HIMALAYAN_PRESSURE_PA:'):
                himalayan_pressure = line.split(':', 1)[1].strip()
            elif line.startswith('SEA_LEVEL_DIFFERENCE:'):
                sea_level_diff = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['target_month'] = target_month
result['dataset_used'] = dataset_used
result['himalayan_pressure'] = himalayan_pressure
result['sea_level_diff'] = sea_level_diff

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="