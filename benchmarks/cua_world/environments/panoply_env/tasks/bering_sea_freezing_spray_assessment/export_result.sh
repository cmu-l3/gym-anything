#!/bin/bash
echo "=== Exporting result for bering_sea_freezing_spray_assessment ==="

TASK_NAME="bering_sea_freezing_spray_assessment"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'bering_sea_freezing_spray_assessment'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/MaritimeSafety'
files = {
    'sst_plot': os.path.join(output_dir, 'bering_sst_jan.png'),
    'airtemp_plot': os.path.join(output_dir, 'bering_airtemp_jan.png'),
    'report': os.path.join(output_dir, 'icing_risk_report.txt'),
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
target_basin = ''
analysis_month = ''
approx_air_temp_c = ''
approx_sst_c = ''
hazard_type = ''
risk_level = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('TARGET_BASIN:'):
                target_basin = line.split(':', 1)[1].strip()
            elif line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('APPROX_AIR_TEMP_C:'):
                approx_air_temp_c = line.split(':', 1)[1].strip()
            elif line.startswith('APPROX_SST_C:'):
                approx_sst_c = line.split(':', 1)[1].strip()
            elif line.startswith('HAZARD_TYPE:'):
                hazard_type = line.split(':', 1)[1].strip()
            elif line.startswith('RISK_LEVEL:'):
                risk_level = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['target_basin'] = target_basin
result['analysis_month'] = analysis_month
result['approx_air_temp_c'] = approx_air_temp_c
result['approx_sst_c'] = approx_sst_c
result['hazard_type'] = hazard_type
result['risk_level'] = risk_level

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="