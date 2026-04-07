#!/bin/bash
echo "=== Exporting result for sahel_drought_teleconnection_analysis ==="

TASK_NAME="sahel_drought_teleconnection_analysis"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'sahel_drought_teleconnection_analysis'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/SahelDrought'
files = {
    'precip_plot': os.path.join(output_dir, 'sahel_precip_july.png'),
    'sst_plot': os.path.join(output_dir, 'pacific_sst_july.png'),
    'report': os.path.join(output_dir, 'teleconnection_report.txt'),
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
analysis_region1 = ''
analysis_region2 = ''
target_season = ''
enso_connection = ''
sahel_precip_pattern = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_REGION_1:'):
                analysis_region1 = line.split(':', 1)[1].strip()
            elif line.startswith('ANALYSIS_REGION_2:'):
                analysis_region2 = line.split(':', 1)[1].strip()
            elif line.startswith('TARGET_SEASON:'):
                target_season = line.split(':', 1)[1].strip()
            elif line.startswith('ENSO_CONNECTION:'):
                enso_connection = line.split(':', 1)[1].strip()
            elif line.startswith('SAHEL_PRECIP_PATTERN:'):
                sahel_precip_pattern = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_region1'] = analysis_region1
result['analysis_region2'] = analysis_region2
result['target_season'] = target_season
result['enso_connection'] = enso_connection
result['sahel_precip_pattern'] = sahel_precip_pattern

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
