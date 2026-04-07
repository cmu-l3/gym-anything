#!/bin/bash
echo "=== Exporting result for mongolian_dzud_climatology_assessment ==="

TASK_NAME="mongolian_dzud_climatology_assessment"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Extract file details and build a JSON result securely
python3 << 'PYEOF'
import json, os, time

task_name = 'mongolian_dzud_climatology_assessment'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/DzudWarning'
files = {
    'precip_plot': os.path.join(output_dir, 'steppe_precip_cycle.png'),
    'temp_plot': os.path.join(output_dir, 'winter_temp_january.png'),
    'report': os.path.join(output_dir, 'baseline_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Assess outputs against timestamps
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
analysis_region = ''
peak_pasture_month = ''
peak_precip_rate = ''
coldest_winter_month = ''
january_mean_temp_c = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_REGION:'):
                analysis_region = line.split(':', 1)[1].strip()
            elif line.startswith('PEAK_PASTURE_MONTH:'):
                peak_pasture_month = line.split(':', 1)[1].strip()
            elif line.startswith('PEAK_PRECIP_RATE:'):
                peak_precip_rate = line.split(':', 1)[1].strip()
            elif line.startswith('COLDEST_WINTER_MONTH:'):
                coldest_winter_month = line.split(':', 1)[1].strip()
            elif line.startswith('JANUARY_MEAN_TEMP_C:'):
                january_mean_temp_c = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_region'] = analysis_region
result['peak_pasture_month'] = peak_pasture_month
result['peak_precip_rate'] = peak_precip_rate
result['coldest_winter_month'] = coldest_winter_month
result['january_mean_temp_c'] = january_mean_temp_c

# Write JSON output
with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="