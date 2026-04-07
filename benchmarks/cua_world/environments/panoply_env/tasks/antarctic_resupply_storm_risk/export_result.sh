#!/bin/bash
echo "=== Exporting result for antarctic_resupply_storm_risk ==="

TASK_NAME="antarctic_resupply_storm_risk"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << PYEOF
import json, os, time

task_start = int(open('${START_TS_FILE}').read().strip()) if os.path.exists('${START_TS_FILE}') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/AntarcticRoute'
files = {
    'png_july': os.path.join(output_dir, 'slp_south_polar_july.png'),
    'png_jan': os.path.join(output_dir, 'slp_south_polar_january.png'),
    'report': os.path.join(output_dir, 'storm_risk_assessment.txt'),
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
parsed_fields = {}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            for line in f.read().splitlines():
                if ':' in line:
                    k, v = line.split(':', 1)
                    parsed_fields[k.strip()] = v.strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['fields'] = parsed_fields

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="