#!/bin/bash
echo "=== Exporting tasseled_cap_transformation result ==="

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import os, json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'bands': {},
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0,
    'png_found': False,
    'png_created_after_start': False,
    'png_file_size': 0
}

# 1. Search for .dim file
dim_path = '/home/ga/snap_exports/tasseled_cap.dim'
if not os.path.exists(dim_path):
    # Fallback search
    for d in ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga', '/home/ga/Desktop']:
        if os.path.exists(d):
            for f in os.listdir(d):
                if f.endswith('.dim') and 'tasseled' in f.lower():
                    dim_path = os.path.join(d, f)
                    break

if os.path.exists(dim_path):
    result['dim_found'] = True
    if int(os.path.getmtime(dim_path)) > task_start:
        result['dim_created_after_start'] = True
        
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = expr_el.text.strip() if (expr_el is not None and expr_el.text) else ''
                result['bands'][bname] = expr_text
    except Exception as e:
        print(f"Error parsing {dim_path}: {e}")

# 2. Search for GeoTIFF
tif_path = '/home/ga/snap_exports/tasseled_cap.tif'
if not os.path.exists(tif_path):
    for d in ['/home/ga/snap_exports', '/home/ga', '/home/ga/Desktop']:
        if os.path.exists(d):
            for f in os.listdir(d):
                if f.endswith('.tif') and 'tasseled' in f.lower():
                    tif_path = os.path.join(d, f)
                    break

if os.path.exists(tif_path):
    result['tif_found'] = True
    result['tif_file_size'] = os.path.getsize(tif_path)
    if int(os.path.getmtime(tif_path)) > task_start:
        result['tif_created_after_start'] = True

# 3. Search for PNG export
png_path = '/home/ga/snap_exports/tct_visualization.png'
if not os.path.exists(png_path):
    for d in ['/home/ga/snap_exports', '/home/ga', '/home/ga/Desktop']:
        if os.path.exists(d):
            for f in os.listdir(d):
                if f.endswith('.png') and ('tct' in f.lower() or 'tasseled' in f.lower() or 'vis' in f.lower()):
                    png_path = os.path.join(d, f)
                    break

if not os.path.exists(png_path):
    # Try any new png created
    for d in ['/home/ga/snap_exports', '/home/ga', '/home/ga/Desktop']:
        if os.path.exists(d):
            for f in os.listdir(d):
                if f.endswith('.png'):
                    p = os.path.join(d, f)
                    if int(os.path.getmtime(p)) > task_start:
                        png_path = p
                        break

if os.path.exists(png_path):
    result['png_found'] = True
    result['png_file_size'] = os.path.getsize(png_path)
    if int(os.path.getmtime(png_path)) > task_start:
        result['png_created_after_start'] = True

with open('/tmp/tct_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/tct_result.json 2>/dev/null || true
echo "Result written to /tmp/tct_result.json"
cat /tmp/tct_result.json
echo ""
echo "=== Export Complete ==="