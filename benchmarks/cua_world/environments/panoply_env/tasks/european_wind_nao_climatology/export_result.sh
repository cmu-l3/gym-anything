#!/bin/bash
echo "=== Exporting result for european_wind_nao_climatology ==="

TASK_NAME="european_wind_nao_climatology"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'european_wind_nao_climatology'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/WindEnergy'
files = {
    'plot': os.path.join(output_dir, 'north_atlantic_slp_jan.png'),
    'report': os.path.join(output_dir, 'nao_baseline_report.txt'),
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

# Parse quantitative fields from the report
report_path = files['report']
iceland_slp = ''
azores_slp = ''
nao_gradient = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ICELAND_SLP_MB:'):
                iceland_slp = line.split(':', 1)[1].strip()
            elif line.startswith('AZORES_SLP_MB:'):
                azores_slp = line.split(':', 1)[1].strip()
            elif line.startswith('NAO_GRADIENT_MB:'):
                nao_gradient = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['iceland_slp'] = iceland_slp
result['azores_slp'] = azores_slp
result['nao_gradient'] = nao_gradient

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="