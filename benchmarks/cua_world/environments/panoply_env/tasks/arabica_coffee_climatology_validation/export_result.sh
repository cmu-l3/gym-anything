#!/bin/bash
echo "=== Exporting result for arabica_coffee_climatology_validation ==="

TASK_NAME="arabica_coffee_climatology_validation"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Copy the CSV to /tmp for easy extraction by verifier
CSV_TARGET="/home/ga/Documents/CoffeeStudy/minas_precip_timeseries.csv"
if [ -f "$CSV_TARGET" ]; then
    cp "$CSV_TARGET" /tmp/minas_precip_timeseries.csv
    chmod 644 /tmp/minas_precip_timeseries.csv
fi

# Write result JSON using Python for safe parsing
python3 << 'PYEOF'
import json, os, time

task_name = 'arabica_coffee_climatology_validation'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/CoffeeStudy'
files = {
    'temp_plot': os.path.join(output_dir, 'minas_temp_cycle.png'),
    'precip_plot': os.path.join(output_dir, 'minas_precip_cycle.png'),
    'csv_data': os.path.join(output_dir, 'minas_precip_timeseries.csv'),
    'report': os.path.join(output_dir, 'coffee_baseline_report.txt'),
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
target_lat = ''
target_lon = ''
coolest_month = ''
driest_month = ''
flowering_sync = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('TARGET_LATITUDE:'):
                target_lat = line.split(':', 1)[1].strip()
            elif line.startswith('TARGET_LONGITUDE:'):
                target_lon = line.split(':', 1)[1].strip()
            elif line.startswith('COOLEST_MONTH:'):
                coolest_month = line.split(':', 1)[1].strip()
            elif line.startswith('DRIEST_MONTH:'):
                driest_month = line.split(':', 1)[1].strip()
            elif line.startswith('FLOWERING_SYNC_POTENTIAL:'):
                flowering_sync = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['target_lat'] = target_lat
result['target_lon'] = target_lon
result['coolest_month'] = coolest_month
result['driest_month'] = driest_month
result['flowering_sync'] = flowering_sync

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="