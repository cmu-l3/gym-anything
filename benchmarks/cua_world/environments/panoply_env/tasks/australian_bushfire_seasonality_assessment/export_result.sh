#!/bin/bash
echo "=== Exporting result for australian_bushfire_seasonality_assessment ==="

TASK_NAME="australian_bushfire_seasonality_assessment"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'australian_bushfire_seasonality_assessment'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/BushfireRisk'
files = {
    'png_jan': os.path.join(output_dir, 'aus_precip_january.png'),
    'png_aug': os.path.join(output_dir, 'aus_precip_august.png'),
    'report': os.path.join(output_dir, 'bushfire_seasonality_report.txt'),
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
january_wet = ''
august_wet = ''
north_fire = ''
south_fire = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('JANUARY_WET_COAST:'):
                january_wet = line.split(':', 1)[1].strip()
            elif line.startswith('AUGUST_WET_COAST:'):
                august_wet = line.split(':', 1)[1].strip()
            elif line.startswith('NORTHERN_PEAK_FIRE_MONTH:'):
                north_fire = line.split(':', 1)[1].strip()
            elif line.startswith('SOUTHERN_PEAK_FIRE_MONTH:'):
                south_fire = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['january_wet_coast'] = january_wet
result['august_wet_coast'] = august_wet
result['northern_peak_fire_month'] = north_fire
result['southern_peak_fire_month'] = south_fire

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="