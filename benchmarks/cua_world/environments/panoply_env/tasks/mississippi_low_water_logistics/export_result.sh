#!/bin/bash
echo "=== Exporting result for mississippi_low_water_logistics ==="

TASK_NAME="mississippi_low_water_logistics"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe JSON encoding and parsing
python3 << 'PYEOF'
import json, os, time

task_name = 'mississippi_low_water_logistics'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/MississippiLogistics'
files = {
    'diff_plot': os.path.join(output_dir, 'midwest_precip_deficit_may_sep.png'),
    'std_plot': os.path.join(output_dir, 'midwest_precip_september.png'),
    'report': os.path.join(output_dir, 'draft_restriction_report.txt'),
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

report_path = files['report']
analysis_months = ''
may_wetter = ''
operational_impact = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTHS:'):
                analysis_months = line.split(':', 1)[1].strip()
            elif line.startswith('MAY_WETTER_THAN_SEP:'):
                may_wetter = line.split(':', 1)[1].strip()
            elif line.startswith('OPERATIONAL_IMPACT:'):
                operational_impact = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_months'] = analysis_months
result['may_wetter'] = may_wetter
result['operational_impact'] = operational_impact

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="