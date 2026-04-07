#!/bin/bash
echo "=== Exporting result for andean_high_hot_aviation_hazard ==="

TASK_NAME="andean_high_hot_aviation_hazard"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Generate result JSON securely
python3 << 'PYEOF'
import json, os, time

task_name = 'andean_high_hot_aviation_hazard'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/AviationLogistics'
files = {
    'pres_plot': os.path.join(output_dir, 'andes_surface_pressure_jan.png'),
    'air_plot': os.path.join(output_dir, 'andes_air_temperature_jan.png'),
    'report': os.path.join(output_dir, 'high_hot_advisory.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Evaluate file metadata
for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Parse report text
report_path = files['report']
month = ''
region = ''
lowest_pressure = ''
aerodynamic_factor = ''
payload_restriction = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ASSESSMENT_MONTH:'):
                month = line.split(':', 1)[1].strip()
            elif line.startswith('TARGET_REGION:'):
                region = line.split(':', 1)[1].strip()
            elif line.startswith('LOWEST_PRESSURE_HPA:'):
                lowest_pressure = line.split(':', 1)[1].strip()
            elif line.startswith('CRITICAL_AERODYNAMIC_FACTOR:'):
                aerodynamic_factor = line.split(':', 1)[1].strip()
            elif line.startswith('PAYLOAD_RESTRICTION_REQUIRED:'):
                payload_restriction = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['assessment_month'] = month
result['target_region'] = region
result['lowest_pressure'] = lowest_pressure
result['aerodynamic_factor'] = aerodynamic_factor
result['payload_restriction'] = payload_restriction

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="