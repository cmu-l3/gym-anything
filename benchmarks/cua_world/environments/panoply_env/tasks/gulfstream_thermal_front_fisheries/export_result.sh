#!/bin/bash
echo "=== Exporting result for gulfstream_thermal_front_fisheries ==="

TASK_NAME="gulfstream_thermal_front_fisheries"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'gulfstream_thermal_front_fisheries'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/GulfStream'
files = {
    'global_plot': os.path.join(output_dir, 'sst_global_feb.png'),
    'zoomed_plot': os.path.join(output_dir, 'gulfstream_front_feb.png'),
    'report': os.path.join(output_dir, 'thermal_front_report.txt'),
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

# Parse report
report_path = files['report']
current_name = ''
analysis_month = ''
warm_side_sst = ''
cold_side_sst = ''
sst_gradient = ''
front_latitude = ''
ecological_significance = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('CURRENT_NAME:'):
                current_name = line.split(':', 1)[1].strip()
            elif line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('WARM_SIDE_SST_C:'):
                warm_side_sst = line.split(':', 1)[1].strip()
            elif line.startswith('COLD_SIDE_SST_C:'):
                cold_side_sst = line.split(':', 1)[1].strip()
            elif line.startswith('SST_GRADIENT_C:'):
                sst_gradient = line.split(':', 1)[1].strip()
            elif line.startswith('FRONT_LATITUDE_N:'):
                front_latitude = line.split(':', 1)[1].strip()
            elif line.startswith('ECOLOGICAL_SIGNIFICANCE:'):
                ecological_significance = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['current_name'] = current_name
result['analysis_month'] = analysis_month
result['warm_side_sst'] = warm_side_sst
result['cold_side_sst'] = cold_side_sst
result['sst_gradient'] = sst_gradient
result['front_latitude'] = front_latitude
result['ecological_significance'] = ecological_significance

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="