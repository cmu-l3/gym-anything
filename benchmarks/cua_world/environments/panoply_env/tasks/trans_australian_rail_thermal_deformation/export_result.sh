#!/bin/bash
echo "=== Exporting result for trans_australian_rail_thermal_deformation ==="

TASK_NAME="trans_australian_rail_thermal_deformation"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'trans_australian_rail_thermal_deformation'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/RailRisk'
files = {
    'png_jan': os.path.join(output_dir, 'australia_jan_heat.png'),
    'png_jul': os.path.join(output_dir, 'australia_jul_cold.png'),
    'report': os.path.join(output_dir, 'thermal_buckling_report.txt'),
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
lat = ''
lon = ''
jan_peak = ''
jul_min = ''
amplitude = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('MAP_CENTER_LAT:'):
                lat = line.split(':', 1)[1].strip()
            elif line.startswith('MAP_CENTER_LON:'):
                lon = line.split(':', 1)[1].strip()
            elif line.startswith('JAN_PEAK_MEAN_K:'):
                jan_peak = line.split(':', 1)[1].strip()
            elif line.startswith('JUL_MIN_MEAN_K:'):
                jul_min = line.split(':', 1)[1].strip()
            elif line.startswith('THERMAL_AMPLITUDE_K:'):
                amplitude = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['lat'] = lat
result['lon'] = lon
result['jan_peak'] = jan_peak
result['jul_min'] = jul_min
result['amplitude'] = amplitude

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="