#!/bin/bash
echo "=== Exporting result for pacific_sst_hovmoller_diagram ==="

TASK_NAME="pacific_sst_hovmoller_diagram"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe JSON encoding
python3 << PYEOF
import json, os, time

task_start = int(open('${START_TS_FILE}').read().strip()) if os.path.exists('${START_TS_FILE}') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/HovmollerLab'
files = {
    'png_plot': os.path.join(output_dir, 'equatorial_sst_hovmoller.png'),
    'report': os.path.join(output_dir, 'hovmoller_analysis.txt'),
}

result = {
    'task_name': '${TASK_NAME}',
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
plot_dimensions = ''
latitude_fixed_value = ''
warmest_pacific_basin = ''
coldest_east_pacific_month = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('PLOT_DIMENSIONS:'):
                plot_dimensions = line.split(':', 1)[1].strip()
            elif line.startswith('LATITUDE_FIXED_VALUE:'):
                latitude_fixed_value = line.split(':', 1)[1].strip()
            elif line.startswith('WARMEST_PACIFIC_BASIN:'):
                warmest_pacific_basin = line.split(':', 1)[1].strip()
            elif line.startswith('COLDEST_EAST_PACIFIC_MONTH:'):
                coldest_east_pacific_month = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['plot_dimensions'] = plot_dimensions
result['latitude_fixed_value'] = latitude_fixed_value
result['warmest_pacific_basin'] = warmest_pacific_basin
result['coldest_east_pacific_month'] = coldest_east_pacific_month

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="