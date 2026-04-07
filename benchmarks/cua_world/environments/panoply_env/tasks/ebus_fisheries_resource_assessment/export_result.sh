#!/bin/bash
echo "=== Exporting result for ebus_fisheries_resource_assessment ==="

TASK_NAME="ebus_fisheries_resource_assessment"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Write result JSON using Python for safe JSON encoding and parsing
python3 << PYEOF
import json, os, time

task_start = int(open('/tmp/${TASK_NAME}_start_ts').read().strip()) if os.path.exists('/tmp/${TASK_NAME}_start_ts') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/UpwellingAssessment'
files = {
    'png_global': os.path.join(output_dir, 'global_sst_july.png'),
    'png_humboldt': os.path.join(output_dir, 'humboldt_upwelling_july.png'),
    'report': os.path.join(output_dir, 'upwelling_report.txt'),
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
fields = {
    'assessment_month': 'ASSESSMENT_MONTH:',
    'primary_ebus': 'PRIMARY_EBUS:',
    'upwelling_sst_c': 'UPWELLING_SST_C:',
    'adjacent_ocean_sst_c': 'ADJACENT_OCEAN_SST_C:',
    'sst_anomaly_sign': 'SST_ANOMALY_SIGN:',
    'productivity_correlation': 'PRODUCTIVITY_CORRELATION:',
    'num_ebus_identified': 'NUM_EBUS_IDENTIFIED:'
}

for k in fields:
    result[k] = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            for key, prefix in fields.items():
                if line.startswith(prefix):
                    result[key] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
cat "${RESULT_JSON}" 2>/dev/null || echo "Warning: result JSON not found"