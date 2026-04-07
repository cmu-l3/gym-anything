#!/bin/bash
echo "=== Exporting result for atacama_observatory_site_validation ==="

TASK_NAME="atacama_observatory_site_validation"

DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'atacama_observatory_site_validation'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/Observatory'
files = {
    'pres_plot': os.path.join(output_dir, 'atacama_pres_jan.png'),
    'precip_plot': os.path.join(output_dir, 'atacama_precip_jan.png'),
    'report': os.path.join(output_dir, 'site_validation_report.txt'),
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
site_name = ''
target_lat = ''
target_lon = ''
jan_pres = ''
jan_precip = ''
eval_month = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('SITE_NAME:'):
                site_name = line.split(':', 1)[1].strip()
            elif line.startswith('TARGET_LAT:'):
                target_lat = line.split(':', 1)[1].strip()
            elif line.startswith('TARGET_LON:'):
                target_lon = line.split(':', 1)[1].strip()
            elif line.startswith('JAN_SURFACE_PRESSURE_PA:'):
                jan_pres = line.split(':', 1)[1].strip()
            elif line.startswith('JAN_PRECIP_RATE:'):
                jan_precip = line.split(':', 1)[1].strip()
            elif line.startswith('EVALUATION_MONTH:'):
                eval_month = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['site_name'] = site_name
result['target_lat'] = target_lat
result['target_lon'] = target_lon
result['jan_pres'] = jan_pres
result['jan_precip'] = jan_precip
result['eval_month'] = eval_month

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="