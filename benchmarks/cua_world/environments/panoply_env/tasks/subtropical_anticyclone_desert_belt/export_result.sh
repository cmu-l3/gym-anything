#!/bin/bash
echo "=== Exporting result for subtropical_anticyclone_desert_belt ==="

TASK_NAME="subtropical_anticyclone_desert_belt"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python
python3 << PYEOF
import json, os, time

task_start = int(open('${START_TS_FILE}').read().strip()) if os.path.exists('${START_TS_FILE}') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/DesertBelt'
files = {
    'slp_png': os.path.join(output_dir, 'slp_global_july.png'),
    'precip_png': os.path.join(output_dir, 'precip_global_july.png'),
    'report': os.path.join(output_dir, 'desert_belt_report.txt'),
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
analysis_month = ''
nh_subtropical_high = ''
associated_desert = ''
mechanism = ''
slp_precip_relationship = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('NH_SUBTROPICAL_HIGH:'):
                nh_subtropical_high = line.split(':', 1)[1].strip()
            elif line.startswith('ASSOCIATED_DESERT:'):
                associated_desert = line.split(':', 1)[1].strip()
            elif line.startswith('MECHANISM:'):
                mechanism = line.split(':', 1)[1].strip()
            elif line.startswith('SLP_PRECIP_RELATIONSHIP:'):
                slp_precip_relationship = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_month'] = analysis_month
result['nh_subtropical_high'] = nh_subtropical_high
result['associated_desert'] = associated_desert
result['mechanism'] = mechanism
result['slp_precip_relationship'] = slp_precip_relationship

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="