#!/bin/bash
echo "=== Exporting result for tibetan_plateau_hypoxia_physiology ==="

TASK_NAME="tibetan_plateau_hypoxia_physiology"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe JSON encoding and parsing
python3 << 'PYEOF'
import json, os, time

task_name = 'tibetan_plateau_hypoxia_physiology'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/HypoxiaStudy'
files = {
    'map_plot': os.path.join(output_dir, 'asia_surface_pressure_july.png'),
    'report': os.path.join(output_dir, 'site_selection_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Check files
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
target_region = ''
dataset_variable_used = ''
ambient_pressure_hpa = ''
physiological_factor = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('TARGET_REGION:'):
                target_region = line.split(':', 1)[1].strip()
            elif line.startswith('DATASET_VARIABLE_USED:'):
                dataset_variable_used = line.split(':', 1)[1].strip()
            elif line.startswith('AMBIENT_PRESSURE_HPA:'):
                ambient_pressure_hpa = line.split(':', 1)[1].strip()
            elif line.startswith('PHYSIOLOGICAL_FACTOR:'):
                physiological_factor = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['target_region'] = target_region
result['dataset_variable_used'] = dataset_variable_used
result['ambient_pressure_hpa'] = ambient_pressure_hpa
result['physiological_factor'] = physiological_factor

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
cat "${RESULT_JSON}" 2>/dev/null || echo "Warning: result JSON not found"