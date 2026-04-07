#!/bin/bash
echo "=== Exporting result for vendee_globe_southern_ocean_risk ==="

TASK_NAME="vendee_globe_southern_ocean_risk"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Extract data using Python
python3 << 'PYEOF'
import json, os, time

task_name = 'vendee_globe_southern_ocean_risk'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/VendeeGlobe'
files = {
    'map_plot': os.path.join(output_dir, 'southern_ocean_slp_jan.png'),
    'report': os.path.join(output_dir, 'route_advisory.txt'),
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
p_30s = ''
p_60s = ''
gradient = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('PRESSURE_30S_20E_HPA:'):
                p_30s = line.split(':', 1)[1].strip()
            elif line.startswith('PRESSURE_60S_20E_HPA:'):
                p_60s = line.split(':', 1)[1].strip()
            elif line.startswith('PRESSURE_GRADIENT_HPA:'):
                gradient = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_month'] = analysis_month
result['p_30s'] = p_30s
result['p_60s'] = p_60s
result['gradient'] = gradient

# Check image dimensions
plot_path = files['map_plot']
if os.path.exists(plot_path):
    try:
        from PIL import Image
        img = Image.open(plot_path)
        result['plot_width'] = img.width
        result['plot_height'] = img.height
    except Exception:
        result['plot_width'] = 0
        result['plot_height'] = 0

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="