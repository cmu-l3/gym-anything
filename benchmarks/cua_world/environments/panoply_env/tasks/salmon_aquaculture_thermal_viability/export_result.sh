#!/bin/bash
echo "=== Exporting result for salmon_aquaculture_thermal_viability ==="

TASK_NAME="salmon_aquaculture_thermal_viability"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe JSON encoding
python3 << 'PYEOF'
import json, os, time

task_name = 'salmon_aquaculture_thermal_viability'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/Aquaculture'
files = {
    'png_summer': os.path.join(output_dir, 'sst_austral_summer_feb.png'),
    'png_winter': os.path.join(output_dir, 'sst_austral_winter_aug.png'),
    'report': os.path.join(output_dir, 'thermal_viability_report.txt'),
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
parsed_data = {
    'PERTH_FEB_SST_C': '',
    'PERTH_VIABILITY': '',
    'TASMANIA_FEB_SST_C': '',
    'TASMANIA_VIABILITY': '',
    'MAGALLANES_FEB_SST_C': '',
    'MAGALLANES_VIABILITY': ''
}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            for key in parsed_data.keys():
                if line.startswith(key + ':'):
                    parsed_data[key] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

for key, value in parsed_data.items():
    result[key] = value

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="