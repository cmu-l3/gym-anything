#!/bin/bash
echo "=== Exporting result for eastern_pacific_itcz_asymmetry_analysis ==="

TASK_NAME="eastern_pacific_itcz_asymmetry_analysis"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'eastern_pacific_itcz_asymmetry_analysis'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ITCZ_Study'
files = {
    'png_jan': os.path.join(output_dir, 'epacific_precip_jan.png'),
    'png_jul': os.path.join(output_dir, 'epacific_precip_jul.png'),
    'report': os.path.join(output_dir, 'itcz_report.txt'),
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
analysis_region = ''
jan_lat = ''
jul_lat = ''
crosses_equator = ''
mechanism = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_REGION:'):
                analysis_region = line.split(':', 1)[1].strip()
            elif line.startswith('JAN_ITCZ_LAT:'):
                jan_lat = line.split(':', 1)[1].strip()
            elif line.startswith('JUL_ITCZ_LAT:'):
                jul_lat = line.split(':', 1)[1].strip()
            elif line.startswith('CROSSES_EQUATOR:'):
                crosses_equator = line.split(':', 1)[1].strip()
            elif line.startswith('DRIVING_MECHANISM:'):
                mechanism = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_region'] = analysis_region
result['jan_lat'] = jan_lat
result['jul_lat'] = jul_lat
result['crosses_equator'] = crosses_equator
result['mechanism'] = mechanism

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="