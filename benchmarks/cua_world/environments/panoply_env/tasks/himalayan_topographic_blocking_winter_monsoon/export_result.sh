#!/bin/bash
echo "=== Exporting result for himalayan_topographic_blocking_winter_monsoon ==="

TASK_NAME="himalayan_topographic_blocking_winter_monsoon"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'himalayan_topographic_blocking_winter_monsoon'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/LectureNotes'
files = {
    'jan_plot': os.path.join(output_dir, 'himalayan_thermal_wall_jan.png'),
    'july_plot': os.path.join(output_dir, 'himalayan_thermal_wall_july.png'),
    'report': os.path.join(output_dir, 'blocking_effect_summary.txt'),
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
india_temp_raw = ''
tibet_temp_raw = ''
temp_diff_raw = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('INDIA_TEMP_C:'):
                india_temp_raw = line.split(':', 1)[1].strip()
            elif line.startswith('TIBET_TEMP_C:'):
                tibet_temp_raw = line.split(':', 1)[1].strip()
            elif line.startswith('TEMP_DIFFERENCE:'):
                temp_diff_raw = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['india_temp_raw'] = india_temp_raw
result['tibet_temp_raw'] = tibet_temp_raw
result['temp_diff_raw'] = temp_diff_raw

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="