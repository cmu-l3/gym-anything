#!/bin/bash
echo "=== Exporting result for continentality_index_array_math ==="

TASK_NAME="continentality_index_array_math"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'continentality_index_array_math'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/Continentality'
files = {
    'plot': os.path.join(output_dir, 'annual_temp_range.png'),
    'report': os.path.join(output_dir, 'biome_report.txt'),
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
operation_used = ''
max_range_region = ''
max_range_value = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('OPERATION_USED:'):
                operation_used = line.split(':', 1)[1].strip()
            elif line.startswith('MAX_RANGE_REGION:'):
                max_range_region = line.split(':', 1)[1].strip()
            elif line.startswith('MAX_RANGE_VALUE:'):
                max_range_value = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['operation_used'] = operation_used
result['max_range_region'] = max_range_region
result['max_range_value'] = max_range_value

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="