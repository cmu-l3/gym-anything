#!/bin/bash
echo "=== Exporting spectral_variability_mapping result ==="

# Source task utils if available
source /workspace/scripts/task_utils.sh 2>/dev/null || source /workspace/utils/task_utils.sh 2>/dev/null || true

# Take final screenshot before processing
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_end.png
else
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true
fi

# Execute Python script to safely parse SNAP DIMAP XML and locate outputs
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/task_start_time.txt'
if os.path.exists(ts_file):
    try:
        task_start = int(open(ts_file).read().strip())
    except:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'dim_file_path': '',
    'bands': {},
    'total_band_count': 0,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0,
    'tif_file_path': ''
}

# 1. Search for .dim files in relevant directories
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim'):
                    full = os.path.join(root, f)
                    if 'snap_data' in full:
                        continue
                    dim_files.append(full)

# Pick the best dim file to inspect (prefer correct naming)
best_dim = None
for dim_file in dim_files:
    if 'spectral_variability' in dim_file.lower():
        best_dim = dim_file
        break
if not best_dim and dim_files:
    best_dim = max(dim_files, key=os.path.getmtime)  # Fallback to newest

if best_dim:
    try:
        mtime = int(os.path.getmtime(best_dim))
        if mtime >= task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True
        result['dim_file_path'] = best_dim

        # Parse DIMAP XML to inspect bands and mathematical expressions
        tree = ET.parse(best_dim)
        root = tree.getroot()

        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['total_band_count'] += 1
                
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = expr_el.text.strip() if (expr_el is not None and expr_el.text) else ''
                
                result['bands'][bname] = {
                    'name': bname,
                    'expression': expr_text
                }
    except Exception as e:
        print(f"Error parsing {best_dim}: {e}")

# 2. Search for GeoTIFF export
tif_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.lower().endswith(('.tif', '.tiff')):
                    full = os.path.join(root, f)
                    if 'snap_data' in full or 'landsat_multispectral' in full:
                        continue
                    tif_files.append(full)

best_tif = None
for tif_file in tif_files:
    if 'spectral_variability' in tif_file.lower():
        best_tif = tif_file
        break
if not best_tif and tif_files:
    best_tif = max(tif_files, key=os.path.getmtime)

if best_tif:
    fsize = os.path.getsize(best_tif)
    mtime = int(os.path.getmtime(best_tif))
    result['tif_found'] = True
    result['tif_file_path'] = best_tif
    result['tif_file_size'] = fsize
    if mtime >= task_start:
        result['tif_created_after_start'] = True

# 3. Export to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="