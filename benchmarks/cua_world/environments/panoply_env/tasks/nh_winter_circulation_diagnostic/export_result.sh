#!/bin/bash
echo "=== Exporting result for nh_winter_circulation_diagnostic ==="

TASK_NAME="nh_winter_circulation_diagnostic"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract data using Python
python3 << 'PYEOF'
import json, os, time

task_name = 'nh_winter_circulation_diagnostic'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/WMO_Briefing'
files = {
    'combine_plot': os.path.join(output_dir, 'nh_circulation_jan.png'),
    'zonal_profile': os.path.join(output_dir, 'zonal_slp_profile.png'),
    'report': os.path.join(output_dir, 'circulation_diagnostic.txt'),
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
icelandic_low = ''
siberian_high = ''
aleutian_low = ''
pressure_contrast = ''
dominant_region = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('ICELANDIC_LOW_SLP_HPA:'):
                icelandic_low = line.split(':', 1)[1].strip()
            elif line.startswith('SIBERIAN_HIGH_SLP_HPA:'):
                siberian_high = line.split(':', 1)[1].strip()
            elif line.startswith('ALEUTIAN_LOW_SLP_HPA:'):
                aleutian_low = line.split(':', 1)[1].strip()
            elif line.startswith('PRESSURE_CONTRAST_HPA:'):
                pressure_contrast = line.split(':', 1)[1].strip()
            elif line.startswith('DOMINANT_HIGH_REGION:'):
                dominant_region = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_month'] = analysis_month
result['icelandic_low_slp'] = icelandic_low
result['siberian_high_slp'] = siberian_high
result['aleutian_low_slp'] = aleutian_low
result['pressure_contrast'] = pressure_contrast
result['dominant_region'] = dominant_region

# Check image dimensions if PIL available
for img_key in ['combine_plot', 'zonal_profile']:
    img_path = files[img_key]
    if os.path.exists(img_path):
        try:
            from PIL import Image
            img = Image.open(img_path)
            result[img_key + '_width'] = img.width
            result[img_key + '_height'] = img.height
        except Exception:
            result[img_key + '_width'] = 0
            result[img_key + '_height'] = 0

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
