#!/bin/bash
echo "=== Exporting result for reanalysis_topographic_smoothing_assessment ==="

TASK_NAME="reanalysis_topographic_smoothing_assessment"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'reanalysis_topographic_smoothing_assessment'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/AgriRisk'
files = {
    'temp_plot': os.path.join(output_dir, 'colombia_temp_annual.png'),
    'precip_plot': os.path.join(output_dir, 'colombia_precip_annual.png'),
    'memo': os.path.join(output_dir, 'veto_memo.txt'),
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

# Parse memo fields
memo_path = files['memo']
dataset_mean_temp_c = ''
model_suitability = ''
error_mechanism = ''
analysis_lat = ''
analysis_lon = ''

if os.path.exists(memo_path):
    try:
        with open(memo_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('DATASET_MEAN_TEMP_C:'):
                dataset_mean_temp_c = line.split(':', 1)[1].strip()
            elif line.startswith('MODEL_SUITABILITY:'):
                model_suitability = line.split(':', 1)[1].strip()
            elif line.startswith('ERROR_MECHANISM:'):
                error_mechanism = line.split(':', 1)[1].strip()
            elif line.startswith('ANALYSIS_LAT:'):
                analysis_lat = line.split(':', 1)[1].strip()
            elif line.startswith('ANALYSIS_LON:'):
                analysis_lon = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse memo: {e}')

result['dataset_mean_temp_c'] = dataset_mean_temp_c
result['model_suitability'] = model_suitability
result['error_mechanism'] = error_mechanism
result['analysis_lat'] = analysis_lat
result['analysis_lon'] = analysis_lon

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="