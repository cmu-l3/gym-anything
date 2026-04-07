#!/bin/bash
echo "=== Exporting result for northwest_passage_thaw_assessment ==="

TASK_NAME="northwest_passage_thaw_assessment"
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

output_dir = '/home/ga/Documents/ArcticRouting'
files = {
    'png_july': os.path.join(output_dir, 'arctic_temp_july.png'),
    'png_august': os.path.join(output_dir, 'arctic_temp_august.png'),
    'report': os.path.join(output_dir, 'nwp_assessment.txt'),
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
projection_used = ''
july_temp_c = ''
august_temp_c = ''
region_analyzed = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('PROJECTION_USED:'):
                projection_used = line.split(':', 1)[1].strip()
            elif line.startswith('JULY_TEMP_C:'):
                july_temp_c = line.split(':', 1)[1].strip()
            elif line.startswith('AUGUST_TEMP_C:'):
                august_temp_c = line.split(':', 1)[1].strip()
            elif line.startswith('REGION_ANALYZED:'):
                region_analyzed = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['projection_used'] = projection_used
result['july_temp_c'] = july_temp_c
result['august_temp_c'] = august_temp_c
result['region_analyzed'] = region_analyzed

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="