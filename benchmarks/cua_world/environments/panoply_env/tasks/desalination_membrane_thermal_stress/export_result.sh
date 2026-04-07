#!/bin/bash
echo "=== Exporting result for desalination_membrane_thermal_stress ==="

TASK_NAME="desalination_membrane_thermal_stress"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe JSON encoding
python3 << PYEOF
import json, os, time

task_start = int(open('/tmp/${TASK_NAME}_start_ts').read().strip()) if os.path.exists('/tmp/${TASK_NAME}_start_ts') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/Desalination'
files = {
    'feb_plot': os.path.join(output_dir, 'egypt_coasts_feb.png'),
    'aug_plot': os.path.join(output_dir, 'egypt_coasts_aug.png'),
    'report': os.path.join(output_dir, 'thermal_envelope_report.txt'),
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

# Parse report fields
report_path = files['report']
med_feb = ''
med_aug = ''
red_sea_feb = ''
red_sea_aug = ''
peak_stress = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('MED_FEB_SST:'):
                med_feb = line.split(':', 1)[1].strip()
            elif line.startswith('MED_AUG_SST:'):
                med_aug = line.split(':', 1)[1].strip()
            elif line.startswith('RED_SEA_FEB_SST:'):
                red_sea_feb = line.split(':', 1)[1].strip()
            elif line.startswith('RED_SEA_AUG_SST:'):
                red_sea_aug = line.split(':', 1)[1].strip()
            elif line.startswith('HIGHEST_PEAK_STRESS:'):
                peak_stress = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['med_feb'] = med_feb
result['med_aug'] = med_aug
result['red_sea_feb'] = red_sea_feb
result['red_sea_aug'] = red_sea_aug
result['peak_stress'] = peak_stress

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="