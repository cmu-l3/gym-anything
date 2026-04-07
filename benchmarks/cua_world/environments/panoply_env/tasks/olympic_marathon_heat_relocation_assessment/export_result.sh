#!/bin/bash
echo "=== Exporting result for olympic_marathon_heat_relocation_assessment ==="

TASK_NAME="olympic_marathon_heat_relocation_assessment"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe JSON encoding and text parsing
python3 << PYEOF
import json, os, time, re

task_name = '${TASK_NAME}'
start_ts_file = '/tmp/' + task_name + '_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/OlympicPlanning'
files = {
    'plot': os.path.join(output_dir, 'japan_august_temp.png'),
    'report': os.path.join(output_dir, 'marathon_relocation_audit.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
    'screenshot_exists': os.path.exists('/tmp/task_final.png')
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

# Parse report fields safely
report_path = files['report']
month = ''
tokyo_c = ''
sapporo_c = ''
diff_c = ''
conclusion = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ASSESSMENT_MONTH:'):
                month = line.split(':', 1)[1].strip()
            elif line.startswith('TOKYO_GRID_TEMP_C:'):
                tokyo_c = line.split(':', 1)[1].strip()
            elif line.startswith('SAPPORO_GRID_TEMP_C:'):
                sapporo_c = line.split(':', 1)[1].strip()
            elif line.startswith('TEMP_DIFFERENCE_C:'):
                diff_c = line.split(':', 1)[1].strip()
            elif line.startswith('MEDICAL_CONCLUSION:'):
                conclusion = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['assessment_month'] = month
result['tokyo_c'] = tokyo_c
result['sapporo_c'] = sapporo_c
result['diff_c'] = diff_c
result['conclusion'] = conclusion

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="