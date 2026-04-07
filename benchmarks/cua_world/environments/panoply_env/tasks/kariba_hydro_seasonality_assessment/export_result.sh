#!/bin/bash
echo "=== Exporting result for kariba_hydro_seasonality_assessment ==="

TASK_NAME="kariba_hydro_seasonality_assessment"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe JSON encoding and parsing
python3 << PYEOF
import json, os, time

task_start = int(open('${START_TS_FILE}').read().strip()) if os.path.exists('${START_TS_FILE}') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/KaribaHydro'
files = {
    'wet_plot': os.path.join(output_dir, 'wet_season_precip.png'),
    'dry_plot': os.path.join(output_dir, 'dry_season_precip.png'),
    'report': os.path.join(output_dir, 'hydro_planning_report.txt'),
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
basin = ''
wettest_month = ''
driest_month = ''
hottest_month = ''
october_temp = ''
evap_risk = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('BASIN:'):
                basin = line.split(':', 1)[1].strip()
            elif line.startswith('WETTEST_MONTH:'):
                wettest_month = line.split(':', 1)[1].strip()
            elif line.startswith('DRIEST_MONTH:'):
                driest_month = line.split(':', 1)[1].strip()
            elif line.startswith('HOTTEST_MONTH:'):
                hottest_month = line.split(':', 1)[1].strip()
            elif line.startswith('OCTOBER_TEMP_K:'):
                october_temp = line.split(':', 1)[1].strip()
            elif line.startswith('EVAPORATION_RISK:'):
                evap_risk = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['basin'] = basin
result['wettest_month'] = wettest_month
result['driest_month'] = driest_month
result['hottest_month'] = hottest_month
result['october_temp_k'] = october_temp
result['evaporation_risk'] = evap_risk

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="