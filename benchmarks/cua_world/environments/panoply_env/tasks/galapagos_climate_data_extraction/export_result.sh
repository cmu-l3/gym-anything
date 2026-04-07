#!/bin/bash
echo "=== Exporting result for galapagos_climate_data_extraction ==="

TASK_NAME="galapagos_climate_data_extraction"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Copy agent's output files to /tmp for the verifier to safely read
OUTPUT_DIR="/home/ga/Documents/Galapagos"
cp "$OUTPUT_DIR/galapagos_temp.csv" "/tmp/${TASK_NAME}_temp.csv" 2>/dev/null || true
cp "$OUTPUT_DIR/galapagos_precip.csv" "/tmp/${TASK_NAME}_precip.csv" 2>/dev/null || true
cp "$OUTPUT_DIR/climate_summary.txt" "/tmp/${TASK_NAME}_summary.txt" 2>/dev/null || true
chmod 666 /tmp/${TASK_NAME}_*.csv /tmp/${TASK_NAME}_*.txt 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'galapagos_climate_data_extraction'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0

output_dir = '/home/ga/Documents/Galapagos'
files = {
    'temp_csv': os.path.join(output_dir, 'galapagos_temp.csv'),
    'precip_csv': os.path.join(output_dir, 'galapagos_precip.csv'),
    'report': os.path.join(output_dir, 'climate_summary.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': int(time.time()),
}

# Record metadata
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

print(f"Result JSON written to /tmp/{task_name}_result.json")
PYEOF

echo "=== Export complete ==="