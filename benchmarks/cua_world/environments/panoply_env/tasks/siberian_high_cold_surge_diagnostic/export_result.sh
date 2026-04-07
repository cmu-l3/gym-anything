#!/bin/bash
echo "=== Exporting result for siberian_high_cold_surge_diagnostic ==="

TASK_NAME="siberian_high_cold_surge_diagnostic"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe JSON encoding
python3 << PYEOF
import json, os, time

task_start_file = '/tmp/${TASK_NAME}_start_ts'
task_start = int(open(task_start_file).read().strip()) if os.path.exists(task_start_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ColdSurge'
files = {
    'jan_plot': os.path.join(output_dir, 'siberian_high_jan.png'),
    'jul_plot': os.path.join(output_dir, 'eurasian_slp_july.png'),
    'report': os.path.join(output_dir, 'cold_surge_diagnostic.txt'),
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

# Define target fields mapped to JSON keys
fields = {
    'CENTER_PRESSURE_HPA': 'center_pressure',
    'CENTER_LATITUDE': 'center_lat',
    'CENTER_LONGITUDE': 'center_lon',
    'SEASONAL_CONTRAST': 'seasonal_contrast',
    'COLD_SURGE_RISK': 'cold_surge_risk',
    'ANALYSIS_SEASON': 'analysis_season'
}

# Initialize all to empty string
for v in fields.values():
    result[v] = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                for k, v in fields.items():
                    if line.startswith(k + ':'):
                        result[v] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
PYEOF

echo "=== Export complete ==="