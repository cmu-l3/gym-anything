#!/bin/bash
echo "=== Exporting result for ipcc_accessible_climate_visualization ==="

TASK_NAME="ipcc_accessible_climate_visualization"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Check application status
APP_RUNNING=$(pgrep -f "Panoply" > /dev/null && echo "true" || echo "false")

python3 << 'PYEOF'
import json, os, time

task_name = 'ipcc_accessible_climate_visualization'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/IPCC_Report'
png_path = os.path.join(output_dir, 'air_temp_july_accessible.png')
report_path = os.path.join(output_dir, 'visualization_metadata.txt')

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
    'png_exists': False,
    'png_size': 0,
    'png_mtime': 0,
    'report_exists': False,
    'report_size': 0,
    'report_mtime': 0,
    'has_pure_red_pixels': False
}

# File stats
if os.path.exists(png_path):
    result['png_exists'] = True
    result['png_size'] = os.path.getsize(png_path)
    result['png_mtime'] = int(os.path.getmtime(png_path))
    
    # Programmatic check for rainbow color scale (pure red pixels)
    # The Panoply default CB-Met has pure red (R>200, G<50, B<50) at the top of the scale
    # Perceptually uniform scales (viridis, cividis, etc.) do NOT have pure red
    try:
        from PIL import Image
        img = Image.open(png_path).convert('RGB')
        # Check a sample of pixels to see if pure red exists
        pixels = list(img.getdata())
        for r, g, b in pixels:
            if r > 200 and g < 50 and b < 50:
                result['has_pure_red_pixels'] = True
                break
    except Exception as e:
        print(f"PIL Image check failed: {e}")

if os.path.exists(report_path):
    result['report_exists'] = True
    result['report_size'] = os.path.getsize(report_path)
    result['report_mtime'] = int(os.path.getmtime(report_path))
    
    # Parse report
    try:
        with open(report_path, 'r', errors='replace') as f:
            lines = f.readlines()
            for line in lines:
                line = line.strip()
                if line.startswith('PROJECTION_USED:'):
                    result['projection_used'] = line.split(':', 1)[1].strip().lower()
                elif line.startswith('CENTER_LONGITUDE:'):
                    result['center_longitude'] = line.split(':', 1)[1].strip()
                elif line.startswith('COLOR_SCALE_USED:'):
                    result['color_scale_used'] = line.split(':', 1)[1].strip().lower()
                elif line.startswith('ACCESSIBILITY_COMPLIANCE:'):
                    result['accessibility_compliance'] = line.split(':', 1)[1].strip().upper()
    except Exception as e:
        print(f"Report parse failed: {e}")

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="