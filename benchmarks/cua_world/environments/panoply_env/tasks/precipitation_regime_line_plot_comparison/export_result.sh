#!/bin/bash
echo "=== Exporting result for precipitation_regime_line_plot_comparison ==="

TASK_NAME="precipitation_regime_line_plot_comparison"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os
import time

task_name = 'precipitation_regime_line_plot_comparison'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/PrecipRegimes'
files = {
    'amazon_plot': os.path.join(output_dir, 'amazon_annual_precip.png'),
    'med_plot': os.path.join(output_dir, 'mediterranean_annual_precip.png'),
    'report': os.path.join(output_dir, 'regime_comparison_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Check files
for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Parse report fields safely
report_path = files['report']
parsed_fields = {
    'amazon_lat': '', 'amazon_lon': '', 'amazon_regime': '', 'amazon_wettest_season': '',
    'med_lat': '', 'med_lon': '', 'med_regime': '', 'med_dry_season': '',
    'regime_contrast': '', 'data_source': ''
}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if line.startswith('AMAZON_LAT:'): parsed_fields['amazon_lat'] = line.split(':', 1)[1].strip()
                elif line.startswith('AMAZON_LON:'): parsed_fields['amazon_lon'] = line.split(':', 1)[1].strip()
                elif line.startswith('AMAZON_REGIME:'): parsed_fields['amazon_regime'] = line.split(':', 1)[1].strip()
                elif line.startswith('AMAZON_WETTEST_SEASON:'): parsed_fields['amazon_wettest_season'] = line.split(':', 1)[1].strip()
                elif line.startswith('MED_LAT:'): parsed_fields['med_lat'] = line.split(':', 1)[1].strip()
                elif line.startswith('MED_LON:'): parsed_fields['med_lon'] = line.split(':', 1)[1].strip()
                elif line.startswith('MED_REGIME:'): parsed_fields['med_regime'] = line.split(':', 1)[1].strip()
                elif line.startswith('MED_DRY_SEASON:'): parsed_fields['med_dry_season'] = line.split(':', 1)[1].strip()
                elif line.startswith('REGIME_CONTRAST:'): parsed_fields['regime_contrast'] = line.split(':', 1)[1].strip()
                elif line.startswith('DATA_SOURCE:'): parsed_fields['data_source'] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f"Warning: could not parse report fully: {e}")

result.update(parsed_fields)

# Check image formats
for key in ['amazon_plot', 'med_plot']:
    path = files[key]
    if os.path.exists(path):
        try:
            from PIL import Image
            img = Image.open(path)
            result[key + '_format'] = img.format
        except Exception:
            result[key + '_format'] = 'unknown'
    else:
        result[key + '_format'] = 'none'

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result JSON written to /tmp/{task_name}_result.json")
PYEOF

echo "=== Export complete ==="