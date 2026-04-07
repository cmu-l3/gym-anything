#!/bin/bash
echo "=== Exporting result for datacenter_free_cooling_site_selection ==="

TASK_NAME="datacenter_free_cooling_site_selection"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'datacenter_free_cooling_site_selection'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/DataCenter'
files = {
    'png_july': os.path.join(output_dir, 'europe_july_temp.png'),
    'png_jan': os.path.join(output_dir, 'europe_jan_temp.png'),
    'report': os.path.join(output_dir, 'site_selection_report.txt'),
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
assessment_month = ''
threshold_temp = ''
selected_candidate = ''
rationale = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ASSESSMENT_MONTH:'):
                assessment_month = line.split(':', 1)[1].strip()
            elif line.startswith('THRESHOLD_TEMP:'):
                threshold_temp = line.split(':', 1)[1].strip()
            elif line.startswith('SELECTED_CANDIDATE:'):
                selected_candidate = line.split(':', 1)[1].strip()
            elif line.startswith('RATIONALE:'):
                rationale = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['assessment_month'] = assessment_month
result['threshold_temp'] = threshold_temp
result['selected_candidate'] = selected_candidate
result['rationale'] = rationale

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="