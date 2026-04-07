#!/bin/bash
echo "=== Exporting euclidean_spectral_target_detection result ==="

# Take final screenshot for visual verification
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

# Run Python script to parse BEAM-DIMAP XML metadata and check files
python3 << 'PYEOF'
import os, json, glob
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/task_start_ts.txt'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_size': 0,
    'spectral_distance_found': False,
    'spectral_distance_expr': '',
    'target_outcrop_found': False,
    'target_outcrop_expr': ''
}

# Find DIMAP metadata files
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
dim_files = []
for d in search_dirs:
    dim_files.extend(glob.glob(os.path.join(d, '*.dim')))

# Filter out base data if any ended up with a .dim extension
dim_files = [f for f in dim_files if 'snap_data' not in f]

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime >= task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        for sbi in root.iter('Spectral_Band_Info'):
            bname_el = sbi.find('BAND_NAME')
            expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
            if bname_el is not None and bname_el.text:
                bname = bname_el.text.strip()
                if bname.lower() == 'spectral_distance':
                    result['spectral_distance_found'] = True
                    if expr_el is not None and expr_el.text:
                        result['spectral_distance_expr'] = expr_el.text.strip()
                elif bname.lower() == 'target_outcrop':
                    result['target_outcrop_found'] = True
                    if expr_el is not None and expr_el.text:
                        result['target_outcrop_expr'] = expr_el.text.strip()
    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# Find GeoTIFF files
tif_files = []
for d in search_dirs:
    tif_files.extend(glob.glob(os.path.join(d, '*.tif')))
tif_files = [f for f in tif_files if 'snap_data' not in f]

for tif_file in tif_files:
    mtime = int(os.path.getmtime(tif_file))
    fsize = os.path.getsize(tif_file)
    if mtime >= task_start and fsize > result['tif_size']:
        result['tif_found'] = True
        result['tif_created_after_start'] = True
        result['tif_size'] = fsize
    elif fsize > result['tif_size']:
        result['tif_found'] = True
        result['tif_size'] = fsize

with open('/tmp/export_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/export_result.json")
PYEOF

echo "=== Export Complete ==="