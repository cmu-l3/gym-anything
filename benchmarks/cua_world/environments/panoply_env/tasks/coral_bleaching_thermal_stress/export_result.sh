#!/bin/bash
echo "=== Exporting result for coral_bleaching_thermal_stress ==="

TASK_NAME="coral_bleaching_thermal_stress"
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
echo "Task start timestamp: $TASK_START"

# Write result JSON using Python for safe JSON encoding
python3 << PYEOF
import json, os, time

task_start = int(open('/tmp/${TASK_NAME}_start_ts').read().strip()) if os.path.exists('/tmp/${TASK_NAME}_start_ts') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ReefStress'
files = {
    'png1': os.path.join(output_dir, 'reef_stress_global_aug.png'),
    'png2': os.path.join(output_dir, 'reef_stress_hotspot.png'),
    'report': os.path.join(output_dir, 'thermal_stress_report.txt'),
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
peak_sst = ''
bleaching_risk = ''
hotspot_region = ''
monitoring_date = ''
regions_assessed = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('PEAK_SST:'):
                peak_sst = line.split(':', 1)[1].strip()
            elif line.startswith('BLEACHING_RISK:'):
                bleaching_risk = line.split(':', 1)[1].strip()
            elif line.startswith('HOTSPOT_REGION:'):
                hotspot_region = line.split(':', 1)[1].strip()
            elif line.startswith('MONITORING_DATE:'):
                monitoring_date = line.split(':', 1)[1].strip()
            elif line.startswith('REGIONS_ASSESSED:'):
                regions_assessed = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['peak_sst'] = peak_sst
result['bleaching_risk'] = bleaching_risk
result['hotspot_region'] = hotspot_region
result['monitoring_date'] = monitoring_date
result['regions_assessed'] = regions_assessed

# Check image validity using Pillow if available
for key, path in [('png1', files['png1']), ('png2', files['png2'])]:
    if os.path.exists(path):
        try:
            from PIL import Image
            img = Image.open(path)
            result[key + '_width'] = img.width
            result[key + '_height'] = img.height
            result[key + '_format'] = img.format
        except Exception:
            result[key + '_width'] = 0
            result[key + '_height'] = 0
            result[key + '_format'] = 'unknown'

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
cat "${RESULT_JSON}" 2>/dev/null || echo "Warning: result JSON not found"
