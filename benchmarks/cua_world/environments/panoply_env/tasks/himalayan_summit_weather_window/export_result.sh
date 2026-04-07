#!/bin/bash
echo "=== Exporting result for himalayan_summit_weather_window ==="

TASK_NAME="himalayan_summit_weather_window"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'himalayan_summit_weather_window'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/Expedition'
files = {
    'precip_may': os.path.join(output_dir, 'himalaya_precip_may.png'),
    'precip_july': os.path.join(output_dir, 'himalaya_precip_july.png'),
    'temp_may': os.path.join(output_dir, 'himalaya_temp_may.png'),
    'report': os.path.join(output_dir, 'summit_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Check file stats
for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Parse report
report_path = files['report']
parsed_data = {
    'target_region': '',
    'preferred_month': '',
    'avalanche_hazard_month': '',
    'hazard_system': '',
    'may_mountain_temp_c': ''
}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if line.startswith('TARGET_REGION:'):
                    parsed_data['target_region'] = line.split(':', 1)[1].strip()
                elif line.startswith('PREFERRED_MONTH:'):
                    parsed_data['preferred_month'] = line.split(':', 1)[1].strip()
                elif line.startswith('AVALANCHE_HAZARD_MONTH:'):
                    parsed_data['avalanche_hazard_month'] = line.split(':', 1)[1].strip()
                elif line.startswith('HAZARD_SYSTEM:'):
                    parsed_data['hazard_system'] = line.split(':', 1)[1].strip()
                elif line.startswith('MAY_MOUNTAIN_TEMP_C:'):
                    parsed_data['may_mountain_temp_c'] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result.update(parsed_data)

# Save result JSON
with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="