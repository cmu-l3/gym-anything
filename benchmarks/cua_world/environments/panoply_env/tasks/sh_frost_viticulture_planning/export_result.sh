#!/bin/bash
echo "=== Exporting result for sh_frost_viticulture_planning ==="

TASK_NAME="sh_frost_viticulture_planning"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'sh_frost_viticulture_planning'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/FrostRisk'
files = {
    'july_plot': os.path.join(output_dir, 'sh_temperature_july.png'),
    'june_plot': os.path.join(output_dir, 'sh_temperature_june.png'),
    'report': os.path.join(output_dir, 'frost_risk_report.txt'),
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
analysis_season = ''
coldest_month = ''
mendoza_risk = ''
western_cape_risk = ''
south_australia_risk = ''
highest_risk_region = ''
threshold_c = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_SEASON:'):
                analysis_season = line.split(':', 1)[1].strip()
            elif line.startswith('COLDEST_MONTH:'):
                coldest_month = line.split(':', 1)[1].strip()
            elif line.startswith('MENDOZA_FROST_RISK:'):
                mendoza_risk = line.split(':', 1)[1].strip()
            elif line.startswith('WESTERN_CAPE_FROST_RISK:'):
                western_cape_risk = line.split(':', 1)[1].strip()
            elif line.startswith('SOUTH_AUSTRALIA_FROST_RISK:'):
                south_australia_risk = line.split(':', 1)[1].strip()
            elif line.startswith('HIGHEST_RISK_REGION:'):
                highest_risk_region = line.split(':', 1)[1].strip()
            elif line.startswith('FROST_THRESHOLD_C:'):
                threshold_c = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_season'] = analysis_season
result['coldest_month'] = coldest_month
result['mendoza_risk'] = mendoza_risk
result['western_cape_risk'] = western_cape_risk
result['south_australia_risk'] = south_australia_risk
result['highest_risk_region'] = highest_risk_region
result['threshold_c'] = threshold_c

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="