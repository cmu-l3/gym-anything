#!/bin/bash
echo "=== Exporting result for freeze_thaw_infrastructure_risk_assessment ==="

TASK_NAME="freeze_thaw_infrastructure_risk_assessment"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe parsing
python3 << PYEOF
import json
import os
import time

task_name = '${TASK_NAME}'
start_ts_file = '${START_TS_FILE}'

task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/FreezeThaw'
files = {
    'png_jan': os.path.join(output_dir, 'temperature_january.png'),
    'png_mar': os.path.join(output_dir, 'temperature_march.png'),
    'report': os.path.join(output_dir, 'freeze_thaw_report.txt'),
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
analysis_months = ''
belt_lat_range = ''
highest_risk_continent = ''
risk_mechanism = ''
mean_temp_c = ''
budget_region = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTHS:'):
                analysis_months = line.split(':', 1)[1].strip()
            elif line.startswith('FREEZE_THAW_BELT_LAT_RANGE_N:'):
                belt_lat_range = line.split(':', 1)[1].strip()
            elif line.startswith('HIGHEST_RISK_CONTINENT:'):
                highest_risk_continent = line.split(':', 1)[1].strip()
            elif line.startswith('RISK_MECHANISM:'):
                risk_mechanism = line.split(':', 1)[1].strip()
            elif line.startswith('MEAN_TEMP_AT_BELT_C:'):
                mean_temp_c = line.split(':', 1)[1].strip()
            elif line.startswith('BUDGET_PRIORITY_REGION:'):
                budget_region = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_months'] = analysis_months
result['belt_lat_range'] = belt_lat_range
result['highest_risk_continent'] = highest_risk_continent
result['risk_mechanism'] = risk_mechanism
result['mean_temp_c'] = mean_temp_c
result['budget_region'] = budget_region

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
PYEOF

chmod 666 "${RESULT_JSON}" 2>/dev/null || sudo chmod 666 "${RESULT_JSON}" 2>/dev/null || true

echo "=== Export complete ==="
cat "${RESULT_JSON}" 2>/dev/null || echo "Warning: result JSON not found"