#!/bin/bash
echo "=== Exporting result for african_itcz_latitudinal_profile ==="

TASK_NAME="african_itcz_latitudinal_profile"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python to safely extract report fields
python3 << PYEOF
import json, os, time

task_start = int(open('${START_TS_FILE}').read().strip()) if os.path.exists('${START_TS_FILE}') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ITCZ_Article'
files = {
    'jan_plot': os.path.join(output_dir, 'itcz_jan_profile.png'),
    'jul_plot': os.path.join(output_dir, 'itcz_jul_profile.png'),
    'report': os.path.join(output_dir, 'itcz_migration_report.txt'),
}

result = {
    'task_name': '${TASK_NAME}',
    'task_start': task_start,
    'timestamp': timestamp,
}

# Check file stats
for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Parse report
report_path = files['report']
jan_peak = ''
jul_peak = ''
migration_direction = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if line.startswith('JAN_PEAK_LATITUDE:'):
                    jan_peak = line.split(':', 1)[1].strip()
                elif line.startswith('JUL_PEAK_LATITUDE:'):
                    jul_peak = line.split(':', 1)[1].strip()
                elif line.startswith('MIGRATION_DIRECTION:'):
                    migration_direction = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['jan_peak'] = jan_peak
result['jul_peak'] = jul_peak
result['migration_direction'] = migration_direction

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
PYEOF

echo "=== Export complete ==="
cat "${RESULT_JSON}" 2>/dev/null || true