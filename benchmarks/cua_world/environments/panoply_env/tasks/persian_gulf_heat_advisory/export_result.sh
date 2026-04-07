#!/bin/bash
echo "=== Exporting result for persian_gulf_heat_advisory ==="

TASK_NAME="persian_gulf_heat_advisory"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'persian_gulf_heat_advisory'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/GulfHeat'
files = {
    'sst_plot': os.path.join(output_dir, 'gulf_sst_august.png'),
    'air_plot': os.path.join(output_dir, 'gulf_airtemp_august.png'),
    'report': os.path.join(output_dir, 'heat_advisory_report.txt'),
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
fields = {
    'ASSESSMENT_REGION': 'region',
    'ASSESSMENT_MONTH': 'month',
    'PEAK_SST_C': 'peak_sst',
    'PEAK_AIR_TEMP_C': 'peak_air',
    'HEAT_RISK_LEVEL': 'risk_level',
    'OUTDOOR_WORK_RESTRICTION': 'restriction',
    'DATA_SOURCES': 'sources'
}

for val in fields.values():
    result[val] = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            for prefix, key in fields.items():
                if line.startswith(f'{prefix}:'):
                    result[key] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="