#!/bin/bash
echo "=== Exporting result for atlantic_hurricane_mdr_extraction ==="

TASK_NAME="atlantic_hurricane_mdr_extraction"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'atlantic_hurricane_mdr_extraction'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/HurricaneResearch'
files = {
    'csv': os.path.join(output_dir, 'mdr_sst_annual.csv'),
    'png': os.path.join(output_dir, 'mdr_map_september.png'),
    'report': os.path.join(output_dir, 'mdr_thermal_report.txt'),
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

# Extract data from CSV to verify self-consistency
csv_content = ""
if result['csv_exists']:
    try:
        with open(files['csv'], 'r') as f:
            csv_content = f.read()
    except Exception as e:
        csv_content = str(e)
result['csv_content'] = csv_content

# Parse report fields
report_path = files['report']
extraction_lat = ''
extraction_lon = ''
peak_sst_value = ''
cyclogenesis_months = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('EXTRACTION_LAT:'):
                extraction_lat = line.split(':', 1)[1].strip()
            elif line.startswith('EXTRACTION_LON:'):
                extraction_lon = line.split(':', 1)[1].strip()
            elif line.startswith('PEAK_SST_VALUE:'):
                peak_sst_value = line.split(':', 1)[1].strip()
            elif line.startswith('CYCLOGENESIS_MONTHS:'):
                cyclogenesis_months = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['report_extraction_lat'] = extraction_lat
result['report_extraction_lon'] = extraction_lon
result['report_peak_sst_value'] = peak_sst_value
result['report_cyclogenesis_months'] = cyclogenesis_months

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="