#!/bin/bash
echo "=== Exporting scatter_plot_soil_line_extraction result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/scatter_plot_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/scatter_plot_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import os
import json

task_start = 0
ts_file = '/tmp/scatter_plot_soil_line_extraction_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'plot_image_found': False,
    'plot_image_size': 0,
    'plot_image_after_start': False,
    'data_file_found': False,
    'data_file_name': "",
    'data_file_size': 0,
    'data_file_after_start': False,
    'data_line_count': 0,
    'has_band_3': False,
    'has_band_2': False
}

search_dirs = ['/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga', '/tmp']

# Find plot image
for d in search_dirs:
    for f in ['soil_line_plot.png', 'soil_line_plot.jpg', 'soil_line_plot.jpeg']:
        path = os.path.join(d, f)
        if os.path.isfile(path):
            result['plot_image_found'] = True
            result['plot_image_size'] = os.path.getsize(path)
            if int(os.path.getmtime(path)) >= task_start:
                result['plot_image_after_start'] = True
            break
    if result['plot_image_found']:
        break

# Find data file
for d in search_dirs:
    for f in ['soil_line_data.txt', 'soil_line_data.csv']:
        path = os.path.join(d, f)
        if os.path.isfile(path):
            result['data_file_found'] = True
            result['data_file_name'] = path
            result['data_file_size'] = os.path.getsize(path)
            if int(os.path.getmtime(path)) >= task_start:
                result['data_file_after_start'] = True
            
            # Count lines and check content for band definitions
            try:
                with open(path, 'r', errors='ignore') as f_in:
                    lines = f_in.readlines()
                    result['data_line_count'] = len(lines)
                    content = "".join(lines).lower()
                    if 'band_3' in content or 'band 3' in content:
                        result['has_band_3'] = True
                    if 'band_2' in content or 'band 2' in content:
                        result['has_band_2'] = True
            except:
                pass
            break
    if result['data_file_found']:
        break

with open('/tmp/scatter_plot_result.json', 'w') as f_out:
    json.dump(result, f_out, indent=2)

print("Result written to /tmp/scatter_plot_result.json")
PYEOF

echo "=== Export Complete ==="