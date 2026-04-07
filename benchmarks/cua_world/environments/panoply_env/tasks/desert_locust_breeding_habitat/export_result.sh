#!/bin/bash
echo "=== Exporting result for desert_locust_breeding_habitat ==="

TASK_NAME="desert_locust_breeding_habitat"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'desert_locust_breeding_habitat'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/LocustAssessment'
files = {
    'precip_plot': os.path.join(output_dir, 'precip_october.png'),
    'temp_plot': os.path.join(output_dir, 'temperature_october.png'),
    'report': os.path.join(output_dir, 'breeding_report.txt'),
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
assessment_month = ''
breeding_zone = ''
breeding_suitability = ''
temperature_suitable = ''
moisture_adequate = ''
temperature_range = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ASSESSMENT_MONTH:'):
                assessment_month = line.split(':', 1)[1].strip()
            elif line.startswith('PRIMARY_BREEDING_ZONE:'):
                breeding_zone = line.split(':', 1)[1].strip()
            elif line.startswith('BREEDING_SUITABILITY:'):
                breeding_suitability = line.split(':', 1)[1].strip()
            elif line.startswith('TEMPERATURE_SUITABLE:'):
                temperature_suitable = line.split(':', 1)[1].strip()
            elif line.startswith('MOISTURE_ADEQUATE:'):
                moisture_adequate = line.split(':', 1)[1].strip()
            elif line.startswith('TEMPERATURE_RANGE_C:'):
                temperature_range = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['assessment_month'] = assessment_month
result['primary_breeding_zone'] = breeding_zone
result['breeding_suitability'] = breeding_suitability
result['temperature_suitable'] = temperature_suitable
result['moisture_adequate'] = moisture_adequate
result['temperature_range'] = temperature_range

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="