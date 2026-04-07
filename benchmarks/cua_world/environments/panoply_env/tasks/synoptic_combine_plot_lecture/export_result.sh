#!/bin/bash
echo "=== Exporting result for synoptic_combine_plot_lecture ==="

TASK_NAME="synoptic_combine_plot_lecture"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time, re

task_name = 'synoptic_combine_plot_lecture'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/SynopticLecture'
files = {
    'combine_plot': os.path.join(output_dir, 'combine_temp_slp_jan.png'),
    'slp_plot': os.path.join(output_dir, 'slp_standalone_jan.png'),
    'notes': os.path.join(output_dir, 'synoptic_teaching_notes.txt'),
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

# Parse notes fields
notes_path = files['notes']
combine_vars = ''
analysis_month = ''
low_name = ''
low_slp = ''
high_name = ''
high_slp = ''

if os.path.exists(notes_path):
    try:
        with open(notes_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('COMBINE_VARIABLES:'):
                combine_vars = line.split(':', 1)[1].strip()
            elif line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('LOW_PRESSURE_CENTER:'):
                low_name = line.split(':', 1)[1].strip()
            elif line.startswith('LOW_CENTER_SLP_HPA:'):
                low_slp = line.split(':', 1)[1].strip()
            elif line.startswith('HIGH_PRESSURE_CENTER:'):
                high_name = line.split(':', 1)[1].strip()
            elif line.startswith('HIGH_CENTER_SLP_HPA:'):
                high_slp = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse teaching notes: {e}')

result['combine_variables'] = combine_vars
result['analysis_month'] = analysis_month
result['low_pressure_center'] = low_name
result['low_center_slp_hpa'] = low_slp
result['high_pressure_center'] = high_name
result['high_center_slp_hpa'] = high_slp

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="