#!/bin/bash
echo "=== Exporting result for continental_temperature_seasonality ==="

TASK_NAME="continental_temperature_seasonality"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to securely parse and export result JSON
python3 << 'PYEOF'
import json, os, time, hashlib

task_name = 'continental_temperature_seasonality'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/Seasonality'
files = {
    'png_jan': os.path.join(output_dir, 'air_temp_january.png'),
    'png_jul': os.path.join(output_dir, 'air_temp_july.png'),
    'report': os.path.join(output_dir, 'seasonality_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

def get_md5(file_path):
    hash_md5 = hashlib.md5()
    try:
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()
    except Exception:
        return ""

for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
        if key.startswith('png'):
            result[key + '_md5'] = get_md5(path)
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0
        if key.startswith('png'):
            result[key + '_md5'] = ""

# Parse report fields
report_path = files['report']
max_seasonality_region = ''
january_temp = ''
july_temp = ''
annual_range_c = ''
physical_mechanism = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('MAX_SEASONALITY_REGION:'):
                max_seasonality_region = line.split(':', 1)[1].strip()
            elif line.startswith('JANUARY_TEMP:'):
                january_temp = line.split(':', 1)[1].strip()
            elif line.startswith('JULY_TEMP:'):
                july_temp = line.split(':', 1)[1].strip()
            elif line.startswith('ANNUAL_RANGE_C:'):
                annual_range_c = line.split(':', 1)[1].strip()
            elif line.startswith('PHYSICAL_MECHANISM:'):
                physical_mechanism = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['max_seasonality_region'] = max_seasonality_region
result['january_temp'] = january_temp
result['july_temp'] = july_temp
result['annual_range_c'] = annual_range_c
result['physical_mechanism'] = physical_mechanism

# Write result to JSON
result_file = f'/tmp/{task_name}_result.json'
with open(result_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to {result_file}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="