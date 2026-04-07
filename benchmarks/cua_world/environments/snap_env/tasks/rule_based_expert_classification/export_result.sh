#!/bin/bash
echo "=== Exporting rule_based_expert_classification result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract data to JSON for verifier
python3 << 'PYEOF'
import os
import json
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
    'tif_size': 0
}

# 1. Search for BEAM-DIMAP file
dim_path = '/home/ga/snap_exports/expert_classification.dim'
if not os.path.exists(dim_path):
    # Fallback search
    for root, dirs, files in os.walk('/home/ga/snap_exports'):
        for f in files:
            if f.endswith('.dim'):
                dim_path = os.path.join(root, f)
                break

if os.path.exists(dim_path):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime >= task_start:
        result['dim_created_after_start'] = True
    
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip().lower()
                band_data = {}
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                if expr_el is not None and expr_el.text:
                    band_data['expression'] = expr_el.text.strip()
                desc_el = sbi.find('DESCRIPTION')
                if desc_el is not None and desc_el.text:
                    band_data['description'] = desc_el.text.strip()
                result['bands'][bname] = band_data
    except Exception as e:
        result['xml_error'] = str(e)

# 2. Search for GeoTIFF
tif_path = '/home/ga/snap_exports/expert_classification.tif'
if not os.path.exists(tif_path):
    for root, dirs, files in os.walk('/home/ga/snap_exports'):
        for f in files:
            if f.endswith('.tif') or f.endswith('.tiff'):
                tif_path = os.path.join(root, f)
                break

if os.path.exists(tif_path):
    result['tif_found'] = True
    mtime = int(os.path.getmtime(tif_path))
    if mtime >= task_start:
        result['tif_created_after_start'] = True
    result['tif_size'] = os.path.getsize(tif_path)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported task results to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="