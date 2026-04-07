#!/bin/bash
echo "=== Exporting result for st_lawrence_seaway_closure_timeseries ==="

TASK_NAME="st_lawrence_seaway_closure_timeseries"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'st_lawrence_seaway_closure_timeseries'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/Seaway'
files = {
    'plot': os.path.join(output_dir, 'st_lawrence_temp_series.png'),
    'report': os.path.join(output_dir, 'shipping_season_report.txt'),
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
coords = ''
coldest_month = ''
sub_freezing = ''
safe_season = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_COORDINATES:'):
                coords = line.split(':', 1)[1].strip()
            elif line.startswith('COLDEST_MONTH:'):
                coldest_month = line.split(':', 1)[1].strip()
            elif line.startswith('SUB_FREEZING_MONTHS:'):
                sub_freezing = line.split(':', 1)[1].strip()
            elif line.startswith('SAFE_SHIPPING_SEASON:'):
                safe_season = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_coords'] = coords
result['coldest_month'] = coldest_month
result['sub_freezing'] = sub_freezing
result['safe_season'] = safe_season

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="