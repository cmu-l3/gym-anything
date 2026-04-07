#!/bin/bash
echo "=== Exporting result for greenland_ablation_onset_analysis ==="

TASK_NAME="greenland_ablation_onset_analysis"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'greenland_ablation_onset_analysis'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/GrISMelt'
files = {
    'png_april': os.path.join(output_dir, 'greenland_temp_april.png'),
    'png_july': os.path.join(output_dir, 'greenland_temp_july.png'),
    'report': os.path.join(output_dir, 'ablation_onset_report.txt'),
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
melt_threshold = ''
april_status = ''
july_margin = ''
july_interior = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('MELT_THRESHOLD_K:'):
                melt_threshold = line.split(':', 1)[1].strip()
            elif line.startswith('APRIL_STATUS:'):
                april_status = line.split(':', 1)[1].strip()
            elif line.startswith('JULY_MARGIN_STATUS:'):
                july_margin = line.split(':', 1)[1].strip()
            elif line.startswith('JULY_INTERIOR_STATUS:'):
                july_interior = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['melt_threshold'] = melt_threshold
result['april_status'] = april_status
result['july_margin_status'] = july_margin
result['july_interior_status'] = july_interior

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="