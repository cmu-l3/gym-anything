#!/bin/bash
echo "=== Exporting result for panama_canal_drought_seasonality ==="

TASK_NAME="panama_canal_drought_seasonality"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Execute a Python script to gather and evaluate all artifacts robustly
python3 << 'PYEOF'
import json, os, time

task_name = 'panama_canal_drought_seasonality'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/CanalAssessment'
files = {
    'line_plot': os.path.join(output_dir, 'annual_precip_profile.png'),
    'map_march': os.path.join(output_dir, 'panama_precip_march.png'),
    'map_october': os.path.join(output_dir, 'panama_precip_october.png'),
    'report': os.path.join(output_dir, 'draft_restriction_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Verify files exist, size and modification times
for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Parse the text report
report_path = files['report']
critical_drought_month = ''
peak_recharge_month = ''
risk_march = ''
risk_october = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('CRITICAL_DROUGHT_MONTH:'):
                critical_drought_month = line.split(':', 1)[1].strip()
            elif line.startswith('PEAK_RECHARGE_MONTH:'):
                peak_recharge_month = line.split(':', 1)[1].strip()
            elif line.startswith('DRAFT_RESTRICTION_RISK_MARCH:'):
                risk_march = line.split(':', 1)[1].strip()
            elif line.startswith('DRAFT_RESTRICTION_RISK_OCTOBER:'):
                risk_october = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['critical_drought_month'] = critical_drought_month
result['peak_recharge_month'] = peak_recharge_month
result['risk_march'] = risk_march
result['risk_october'] = risk_october

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="