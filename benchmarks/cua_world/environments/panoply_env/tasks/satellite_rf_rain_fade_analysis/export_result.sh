#!/bin/bash
echo "=== Exporting result for satellite_rf_rain_fade_analysis ==="

TASK_NAME="satellite_rf_rain_fade_analysis"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'satellite_rf_rain_fade_analysis'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/RainFade'
files = {
    'plot': os.path.join(output_dir, 'jakarta_precip_timeseries.png'),
    'report': os.path.join(output_dir, 'rf_fade_margin_report.txt'),
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
gateway_location = ''
grid_latitude = ''
grid_longitude = ''
peak_rain_month = ''
peak_prate_value = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('GATEWAY_LOCATION:'):
                gateway_location = line.split(':', 1)[1].strip()
            elif line.startswith('GRID_LATITUDE:'):
                grid_latitude = line.split(':', 1)[1].strip()
            elif line.startswith('GRID_LONGITUDE:'):
                grid_longitude = line.split(':', 1)[1].strip()
            elif line.startswith('PEAK_RAIN_MONTH:'):
                peak_rain_month = line.split(':', 1)[1].strip()
            elif line.startswith('PEAK_PRATE_VALUE:'):
                peak_prate_value = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['gateway_location'] = gateway_location
result['grid_latitude'] = grid_latitude
result['grid_longitude'] = grid_longitude
result['peak_rain_month'] = peak_rain_month
result['peak_prate_value'] = peak_prate_value

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="