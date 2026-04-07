#!/bin/bash
echo "=== Exporting result for nh_snowmelt_isotherm_planning ==="

TASK_NAME="nh_snowmelt_isotherm_planning"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to securely parse files and write JSON
python3 << 'PYEOF'
import json
import os
import time

task_name = 'nh_snowmelt_isotherm_planning'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/SnowmeltPlan'
files = {
    'feb_plot': os.path.join(output_dir, 'air_temp_february.png'),
    'mar_plot': os.path.join(output_dir, 'air_temp_march.png'),
    'apr_plot': os.path.join(output_dir, 'air_temp_april.png'),
    'report': os.path.join(output_dir, 'snowmelt_timing_report.txt'),
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

# Parse report fields safely
report_path = files['report']
report_data = {
    'target_basin': '',
    'months_compared': '',
    'snowmelt_onset_month': '',
    'freezing_threshold': '',
    'temperature_unit': ''
}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('TARGET_BASIN:'):
                report_data['target_basin'] = line.split(':', 1)[1].strip()
            elif line.startswith('MONTHS_COMPARED:'):
                report_data['months_compared'] = line.split(':', 1)[1].strip()
            elif line.startswith('SNOWMELT_ONSET_MONTH:'):
                report_data['snowmelt_onset_month'] = line.split(':', 1)[1].strip()
            elif line.startswith('FREEZING_THRESHOLD:'):
                report_data['freezing_threshold'] = line.split(':', 1)[1].strip()
            elif line.startswith('TEMPERATURE_UNIT:'):
                report_data['temperature_unit'] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result.update(report_data)

# Check image validity and dimensions if Pillow is available
for key in ['feb_plot', 'mar_plot', 'apr_plot']:
    path = files[key]
    if os.path.exists(path):
        try:
            from PIL import Image
            img = Image.open(path)
            result[key + '_valid'] = True
            result[key + '_width'] = img.width
            result[key + '_height'] = img.height
        except Exception:
            result[key + '_valid'] = False
            result[key + '_width'] = 0
            result[key + '_height'] = 0

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
# print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="