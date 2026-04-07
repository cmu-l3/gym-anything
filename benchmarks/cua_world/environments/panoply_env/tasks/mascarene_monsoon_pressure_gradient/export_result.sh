#!/bin/bash
echo "=== Exporting result for mascarene_monsoon_pressure_gradient ==="

TASK_NAME="mascarene_monsoon_pressure_gradient"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << PYEOF
import json, os, time

task_start = int(open('/tmp/${TASK_NAME}_start_ts').read().strip()) if os.path.exists('/tmp/${TASK_NAME}_start_ts') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/MaritimeRouting'
files = {
    'plot': os.path.join(output_dir, 'indian_ocean_slp_july.png'),
    'report': os.path.join(output_dir, 'monsoon_gradient_report.txt'),
}

result = {
    'task_name': '${TASK_NAME}',
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
fields_to_extract = [
    'ANALYSIS_MONTH', 'MASCARENE_HIGH_LAT', 'MASCARENE_HIGH_LON', 'MASCARENE_HIGH_MB',
    'MONSOON_LOW_LAT', 'MONSOON_LOW_LON', 'MONSOON_LOW_MB', 'GRADIENT_DELTA_MB', 'PRIMARY_MARITIME_HAZARD'
]

for field in fields_to_extract:
    result[field.lower()] = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            for field in fields_to_extract:
                if line.startswith(field + ':'):
                    result[field.lower()] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
PYEOF

echo "=== Export complete ==="