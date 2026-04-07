#!/bin/bash
echo "=== Exporting result for north_atlantic_maritime_slp_assessment ==="

TASK_NAME="north_atlantic_maritime_slp_assessment"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot as evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for parsing safety
python3 << 'PYEOF'
import json, os, time, re

task_name = 'north_atlantic_maritime_slp_assessment'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/MaritimeRouting'
files = {
    'jan_plot': os.path.join(output_dir, 'slp_january.png'),
    'jul_plot': os.path.join(output_dir, 'slp_july.png'),
    'report': os.path.join(output_dir, 'routing_advisory.txt'),
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
icelandic_low_hpa = ''
bermuda_high_hpa = ''
winter_route = ''
primary_basin = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ICELANDIC_LOW_SLP_HPA:'):
                icelandic_low_hpa = line.split(':', 1)[1].strip()
            elif line.startswith('BERMUDA_HIGH_SLP_HPA:'):
                bermuda_high_hpa = line.split(':', 1)[1].strip()
            elif line.startswith('RECOMMENDED_WINTER_ROUTE:'):
                winter_route = line.split(':', 1)[1].strip()
            elif line.startswith('PRIMARY_WINTER_STORM_BASIN:'):
                primary_basin = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['icelandic_low_hpa'] = icelandic_low_hpa
result['bermuda_high_hpa'] = bermuda_high_hpa
result['winter_route'] = winter_route
result['primary_basin'] = primary_basin

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="