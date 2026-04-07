#!/bin/bash
echo "=== Exporting result for malaria_transmission_suitability_mapping ==="

TASK_NAME="malaria_suitability"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Extract data using Python to ensure clean JSON handling
python3 << 'PYEOF'
import json, os, time

task_name = 'malaria_suitability'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/MalariaSuitability'
files = {
    'temp_plot': os.path.join(output_dir, 'temperature_july.png'),
    'precip_plot': os.path.join(output_dir, 'precipitation_july.png'),
    'report': os.path.join(output_dir, 'transmission_suitability_report.txt'),
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

# Parse report fields safely
report_path = files['report']
analysis_month = ''
temp_suitability = ''
primary_zone = ''
secondary_zone = ''
suitability_level = ''
datasets_used = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('TEMP_SUITABILITY_RANGE_C:'):
                temp_suitability = line.split(':', 1)[1].strip()
            elif line.startswith('PRIMARY_RISK_ZONE:'):
                primary_zone = line.split(':', 1)[1].strip()
            elif line.startswith('SECONDARY_RISK_ZONE:'):
                secondary_zone = line.split(':', 1)[1].strip()
            elif line.startswith('TRANSMISSION_SUITABILITY:'):
                suitability_level = line.split(':', 1)[1].strip()
            elif line.startswith('DATASETS_USED:'):
                datasets_used = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_month'] = analysis_month
result['temp_suitability'] = temp_suitability
result['primary_zone'] = primary_zone
result['secondary_zone'] = secondary_zone
result['suitability_level'] = suitability_level
result['datasets_used'] = datasets_used

# Calculate difference in plot sizes (to catch identical copies)
if result['temp_plot_exists'] and result['precip_plot_exists']:
    result['plot_size_diff'] = abs(result['temp_plot_size'] - result['precip_plot_size'])
else:
    result['plot_size_diff'] = -1

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

cat /tmp/malaria_suitability_result.json

echo "=== Export complete ==="