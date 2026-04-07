#!/bin/bash
echo "=== Exporting result for naval_asw_sonar_thermal_amplitude ==="

TASK_NAME="naval_asw_sonar_thermal_amplitude"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Read task start timestamp
TASK_START=0
if [[ -f "$START_TS_FILE" ]]; then
    TASK_START=$(cat "$START_TS_FILE")
fi

python3 << PYEOF
import json, os, time

task_start = $TASK_START
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ASWOceanography'
files = {
    'plot': os.path.join(output_dir, 'sst_amplitude_aug_feb.png'),
    'report': os.path.join(output_dir, 'thermal_amplitude_report.txt'),
}

result = {
    'task_name': '${TASK_NAME}',
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
assessment_type = ''
month_1 = ''
month_2 = ''
max_amplitude = ''
peak_region = ''
tactical_impact = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ASSESSMENT_TYPE:'):
                assessment_type = line.split(':', 1)[1].strip()
            elif line.startswith('MONTH_1:'):
                month_1 = line.split(':', 1)[1].strip()
            elif line.startswith('MONTH_2:'):
                month_2 = line.split(':', 1)[1].strip()
            elif line.startswith('MAX_AMPLITUDE_C:'):
                max_amplitude = line.split(':', 1)[1].strip()
            elif line.startswith('PEAK_REGION:'):
                peak_region = line.split(':', 1)[1].strip()
            elif line.startswith('TACTICAL_IMPACT:'):
                tactical_impact = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['assessment_type'] = assessment_type
result['month_1'] = month_1
result['month_2'] = month_2
result['max_amplitude'] = max_amplitude
result['peak_region'] = peak_region
result['tactical_impact'] = tactical_impact

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="