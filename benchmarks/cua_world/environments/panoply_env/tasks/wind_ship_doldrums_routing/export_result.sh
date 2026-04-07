#!/bin/bash
echo "=== Exporting result for wind_ship_doldrums_routing ==="

TASK_NAME="wind_ship_doldrums_routing"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python parser to reliably extract state and report data
python3 << 'PYEOF'
import json
import os
import time

task_name = 'wind_ship_doldrums_routing'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/SailRouting'
files = {
    'plot': os.path.join(output_dir, 'atlantic_slp_september.png'),
    'report': os.path.join(output_dir, 'doldrums_crossing_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Verify file presence and timestamps
for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Parse text report fields
report_path = files['report']
parsed_fields = {
    'analysis_month': '',
    'ocean_basin': '',
    'doldrums_lat': '',
    'min_slp': '',
    'equator_offset': ''
}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTH:'):
                parsed_fields['analysis_month'] = line.split(':', 1)[1].strip()
            elif line.startswith('OCEAN_BASIN:'):
                parsed_fields['ocean_basin'] = line.split(':', 1)[1].strip()
            elif line.startswith('DOLDRUMS_LATITUDE_N:'):
                parsed_fields['doldrums_lat'] = line.split(':', 1)[1].strip()
            elif line.startswith('MIN_EQUATORIAL_SLP_HPA:'):
                parsed_fields['min_slp'] = line.split(':', 1)[1].strip()
            elif line.startswith('METEOROLOGICAL_EQUATOR_OFFSET:'):
                parsed_fields['equator_offset'] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result.update(parsed_fields)

# Write to JSON
result_file = f'/tmp/{task_name}_result.json'
with open(result_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to {result_file}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="