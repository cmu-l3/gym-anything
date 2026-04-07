#!/bin/bash
echo "=== Exporting result for svalbard_spitsbergen_current_winter_anomaly ==="

TASK_NAME="svalbard_spitsbergen_current_winter_anomaly"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'svalbard_spitsbergen_current_winter_anomaly'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ArcticResearch'
files = {
    'plot': os.path.join(output_dir, 'arctic_sst_february.png'),
    'report': os.path.join(output_dir, 'spitsbergen_anomaly_report.txt'),
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
analysis_month = ''
projection_used = ''
svalbard_sst = ''
canadian_sst = ''
warming_mechanism = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('PROJECTION_USED:'):
                projection_used = line.split(':', 1)[1].strip()
            elif line.startswith('SVALBARD_WEST_SST_C:'):
                svalbard_sst = line.split(':', 1)[1].strip()
            elif line.startswith('CANADIAN_ARCTIC_SST_C:'):
                canadian_sst = line.split(':', 1)[1].strip()
            elif line.startswith('WARMING_MECHANISM:'):
                warming_mechanism = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_month'] = analysis_month
result['projection_used'] = projection_used
result['svalbard_sst'] = svalbard_sst
result['canadian_sst'] = canadian_sst
result['warming_mechanism'] = warming_mechanism

# Check image size/format via Pillow if available
plot_path = files['plot']
if os.path.exists(plot_path):
    try:
        from PIL import Image
        img = Image.open(plot_path)
        result['plot_width'] = img.width
        result['plot_height'] = img.height
    except Exception:
        pass

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="