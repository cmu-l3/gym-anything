#!/bin/bash
echo "=== Exporting result for hokkaido_drift_ice_thermal_forcing ==="

TASK_NAME="hokkaido_drift_ice_thermal_forcing"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Execute Python script to gather and safely format the JSON results
python3 << 'PYEOF'
import json
import os
import time

task_name = 'hokkaido_drift_ice_thermal_forcing'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/Ryuhyo'
files = {
    'airtemp_plot': os.path.join(output_dir, 'okhotsk_airtemp_feb.png'),
    'slp_plot': os.path.join(output_dir, 'okhotsk_slp_feb.png'),
    'report': os.path.join(output_dir, 'thermal_forcing_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Check file existence, sizes, and mtimes
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
analysis_month = ''
region = ''
min_air_temp = ''
siberian_high_slp = ''
inferred_wind = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('REGION:'):
                region = line.split(':', 1)[1].strip()
            elif line.startswith('MIN_AIR_TEMP_NORTH_OKHOTSK:'):
                min_air_temp = line.split(':', 1)[1].strip()
            elif line.startswith('SIBERIAN_HIGH_CENTER_SLP_HPA:'):
                siberian_high_slp = line.split(':', 1)[1].strip()
            elif line.startswith('INFERRED_WIND:'):
                inferred_wind = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_month'] = analysis_month
result['region'] = region
result['min_air_temp'] = min_air_temp
result['siberian_high_slp'] = siberian_high_slp
result['inferred_wind'] = inferred_wind

# Write out the result JSON
with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="