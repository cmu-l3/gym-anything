#!/bin/bash
echo "=== Exporting result for lithium_brine_evaporation_climatology ==="

TASK_NAME="lithium_brine_evaporation_climatology"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python
python3 << PYEOF
import json, os, time

task_start = int(open('/tmp/${TASK_NAME}_start_ts').read().strip()) if os.path.exists('/tmp/${TASK_NAME}_start_ts') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/LithiumProspecting'
files = {
    'tibet_png': os.path.join(output_dir, 'tibet_temp_jan.png'),
    'andes_png': os.path.join(output_dir, 'andes_temp_jan.png'),
    'report': os.path.join(output_dir, 'evaporation_feasibility.txt'),
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
tibet_temp = ''
andes_temp = ''
feasibility = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('TIBET_JAN_TEMP_C:'):
                tibet_temp = line.split(':', 1)[1].strip()
            elif line.startswith('ANDES_JAN_TEMP_C:'):
                andes_temp = line.split(':', 1)[1].strip()
            elif line.startswith('WINTER_EVAPORATION_FEASIBLE_TIBET:'):
                feasibility = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['tibet_temp'] = tibet_temp
result['andes_temp'] = andes_temp
result['feasibility'] = feasibility

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="