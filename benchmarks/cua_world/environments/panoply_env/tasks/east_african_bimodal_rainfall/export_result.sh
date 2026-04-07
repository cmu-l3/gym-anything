#!/bin/bash
echo "=== Exporting result for east_african_bimodal_rainfall ==="

TASK_NAME="east_african_bimodal_rainfall"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'east_african_bimodal_rainfall'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/EastAfricaRainfall'
files = {
    'map_plot': os.path.join(output_dir, 'precip_map_april.png'),
    'line_plot': os.path.join(output_dir, 'annual_cycle_lineplot.png'),
    'report': os.path.join(output_dir, 'rainfall_assessment.txt'),
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
        
        # Check image dimensions using Pillow if available
        if key.endswith('_plot'):
            try:
                from PIL import Image
                img = Image.open(path)
                result[key + '_width'] = img.width
                result[key + '_height'] = img.height
            except Exception:
                result[key + '_width'] = 0
                result[key + '_height'] = 0
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Parse report fields
report_path = files['report']
report_data = {
    'rainfall_pattern': '',
    'long_rains_peak': '',
    'short_rains_peak': '',
    'grid_point_lat': '',
    'grid_point_lon': ''
}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('RAINFALL_PATTERN:'):
                report_data['rainfall_pattern'] = line.split(':', 1)[1].strip()
            elif line.startswith('LONG_RAINS_PEAK:'):
                report_data['long_rains_peak'] = line.split(':', 1)[1].strip()
            elif line.startswith('SHORT_RAINS_PEAK:'):
                report_data['short_rains_peak'] = line.split(':', 1)[1].strip()
            elif line.startswith('GRID_POINT_LAT:'):
                report_data['grid_point_lat'] = line.split(':', 1)[1].strip()
            elif line.startswith('GRID_POINT_LON:'):
                report_data['grid_point_lon'] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result.update(report_data)

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="