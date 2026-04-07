#!/bin/bash
echo "=== Exporting result for corn_belt_agritech_data_extraction ==="

TASK_NAME="corn_belt_agritech_data_extraction"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Copy agent's files to /tmp/ so copy_from_env can easily grab them
OUTPUT_DIR="/home/ga/Documents/AgTech"
cp "$OUTPUT_DIR/iowa_temp_climatology.csv" "/tmp/iowa_temp_climatology.csv" 2>/dev/null || true
cp "$OUTPUT_DIR/iowa_precip_climatology.csv" "/tmp/iowa_precip_climatology.csv" 2>/dev/null || true
cp "$OUTPUT_DIR/feature_summary.txt" "/tmp/feature_summary.txt" 2>/dev/null || true

chmod 666 /tmp/iowa_temp_climatology.csv /tmp/iowa_precip_climatology.csv /tmp/feature_summary.txt 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'corn_belt_agritech_data_extraction'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/AgTech'
files = {
    'temp_csv': os.path.join(output_dir, 'iowa_temp_climatology.csv'),
    'precip_csv': os.path.join(output_dir, 'iowa_precip_climatology.csv'),
    'report': os.path.join(output_dir, 'feature_summary.txt'),
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

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="