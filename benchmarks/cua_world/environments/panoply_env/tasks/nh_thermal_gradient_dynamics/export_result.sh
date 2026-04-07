#!/bin/bash
echo "=== Exporting result for nh_thermal_gradient_dynamics ==="

TASK_NAME="nh_thermal_gradient_dynamics"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'nh_thermal_gradient_dynamics'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ThermalDynamics'
files = {
    'png_jan': os.path.join(output_dir, 'zonal_temp_jan.png'),
    'png_jul': os.path.join(output_dir, 'zonal_temp_jul.png'),
    'report': os.path.join(output_dir, 'gradient_report.txt'),
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
jan_grad = ''
jul_grad = ''
stronger_jet = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('JAN_GRADIENT_MAGNITUDE:'):
                jan_grad = line.split(':', 1)[1].strip()
            elif line.startswith('JUL_GRADIENT_MAGNITUDE:'):
                jul_grad = line.split(':', 1)[1].strip()
            elif line.startswith('STRONGER_JET_MONTH:'):
                stronger_jet = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['jan_gradient'] = jan_grad
result['jul_gradient'] = jul_grad
result['stronger_jet'] = stronger_jet

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="