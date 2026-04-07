#!/bin/bash
echo "=== Exporting result for andean_rain_shadow_cross_section ==="

TASK_NAME="andean_rain_shadow_cross_section"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for robust parsing and formatting
python3 << PYEOF
import json, os, time

task_start = int(open('${START_TS_FILE}').read().strip()) if os.path.exists('${START_TS_FILE}') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/OrographicStudy'
files = {
    'plot': os.path.join(output_dir, 'andean_cross_section.png'),
    'report': os.path.join(output_dir, 'rain_shadow_report.txt'),
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
study_region = ''
latitude_slice = ''
peak_lon = ''
min_lon = ''
effect = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('STUDY_REGION:'):
                study_region = line.split(':', 1)[1].strip()
            elif line.startswith('LATITUDE_SLICE:'):
                latitude_slice = line.split(':', 1)[1].strip()
            elif line.startswith('PEAK_WINDWARD_PRECIP_LON:'):
                peak_lon = line.split(':', 1)[1].strip()
            elif line.startswith('MIN_LEEWARD_PRECIP_LON:'):
                min_lon = line.split(':', 1)[1].strip()
            elif line.startswith('METEOROLOGICAL_EFFECT:'):
                effect = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['study_region'] = study_region
result['latitude_slice'] = latitude_slice
result['peak_windward_precip_lon'] = peak_lon
result['min_leeward_precip_lon'] = min_lon
result['meteorological_effect'] = effect

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="