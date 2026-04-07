#!/bin/bash
echo "=== Exporting result for european_heatwave_synoptic_assessment ==="

TASK_NAME="european_heatwave_synoptic_assessment"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'european_heatwave_synoptic_assessment'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/HeatwaveAssessment'
files = {
    'temp_plot': os.path.join(output_dir, 'europe_temp_july.png'),
    'slp_plot': os.path.join(output_dir, 'europe_slp_july.png'),
    'report': os.path.join(output_dir, 'heatwave_assessment.txt'),
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
assessment_period = ''
dominant_pressure_system = ''
slp_center_hpa = ''
southern_europe_temp_c = ''
highest_risk_region = ''
heatwave_mechanism = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ASSESSMENT_PERIOD:'):
                assessment_period = line.split(':', 1)[1].strip()
            elif line.startswith('DOMINANT_PRESSURE_SYSTEM:'):
                dominant_pressure_system = line.split(':', 1)[1].strip()
            elif line.startswith('SLP_CENTER_HPA:'):
                slp_center_hpa = line.split(':', 1)[1].strip()
            elif line.startswith('SOUTHERN_EUROPE_TEMP_C:'):
                southern_europe_temp_c = line.split(':', 1)[1].strip()
            elif line.startswith('HIGHEST_RISK_REGION:'):
                highest_risk_region = line.split(':', 1)[1].strip()
            elif line.startswith('HEATWAVE_MECHANISM:'):
                heatwave_mechanism = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['assessment_period'] = assessment_period
result['dominant_pressure_system'] = dominant_pressure_system
result['slp_center_hpa'] = slp_center_hpa
result['southern_europe_temp_c'] = southern_europe_temp_c
result['highest_risk_region'] = highest_risk_region
result['heatwave_mechanism'] = heatwave_mechanism

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="