#!/bin/bash
echo "=== Exporting ag_prescription_map_msavi2 result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/ag_prescription_final.png 2>/dev/null || true

# We will use Python to parse the SNAP DIMAP XML files to extract band expressions
# and check file timestamps.
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/ag_prescription_task_start_ts'
if os.path.exists(ts_file):
    with open(ts_file, 'r') as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'msavi2_band_found': False,
    'msavi2_expression': '',
    'zones_band_found': False,
    'zones_expression': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# 1. Search for .dim files in the exports (and projects) directories
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
dim_files = []

for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim'):
                    full_path = os.path.join(root, f)
                    if 'snap_data' in full_path:
                        continue
                    dim_files.append(full_path)

msavi2_keywords = ['msavi2', 'msavi']
zones_keywords = ['management_zones', 'zones', 'prescription', 'classification']

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        # Extract spectral bands and their expressions
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                bname_lower = bname.lower()
                
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = ''
                if expr_el is not None and expr_el.text:
                    expr_text = expr_el.text.strip()

                # Check for MSAVI2 band
                if any(kw in bname_lower for kw in msavi2_keywords):
                    result['msavi2_band_found'] = True
                    if expr_text:
                        result['msavi2_expression'] = expr_text

                # Check for Management Zones band
                if any(kw in bname_lower for kw in zones_keywords):
                    result['zones_band_found'] = True
                    if expr_text:
                        result['zones_expression'] = expr_text

    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# 2. Search for GeoTIFF exports
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.lower().endswith(('.tif', '.tiff')):
                    full_path = os.path.join(root, f)
                    if 'snap_data' in full_path:
                        continue
                    
                    fsize = os.path.getsize(full_path)
                    mtime = int(os.path.getmtime(full_path))
                    
                    if mtime > task_start and fsize > result['tif_file_size']:
                        result['tif_found'] = True
                        result['tif_created_after_start'] = True
                        result['tif_file_size'] = fsize

# Save results for verifier
with open('/tmp/ag_prescription_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON saved to /tmp/ag_prescription_result.json")
PYEOF

echo "=== Export Complete ==="