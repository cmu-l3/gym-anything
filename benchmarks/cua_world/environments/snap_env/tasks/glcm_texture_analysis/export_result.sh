#!/bin/bash
echo "=== Exporting GLCM Texture Analysis result ==="

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Run Python parser inside the container to read output properties robustly
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

START_TIME_FILE = "/tmp/task_start_time.txt"
task_start = 0
if os.path.exists(START_TIME_FILE):
    try:
        task_start = int(open(START_TIME_FILE).read().strip())
    except:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'dim_data_dir_found': False,
    'band_names': [],
    'virtual_bands': {},
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# 1. Check DIMAP Output
dim_file = "/home/ga/snap_exports/landsat_texture.dim"
data_dir = "/home/ga/snap_exports/landsat_texture.data"

if os.path.exists(dim_file):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_file))
    if mtime >= task_start:
        result['dim_created_after_start'] = True
    
    if os.path.isdir(data_dir):
        result['dim_data_dir_found'] = True

    # Parse XML for band information
    try:
        tree = ET.parse(dim_file)
        root = tree.getroot()
        for sbi in root.iter("Spectral_Band_Info"):
            name_el = sbi.find("BAND_NAME")
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['band_names'].append(bname)
                
                # Check for virtual band
                virt_el = sbi.find("VIRTUAL_BAND")
                if virt_el is not None and virt_el.text and virt_el.text.lower() == 'true':
                    expr_el = sbi.find("VIRTUAL_BAND_EXPRESSION")
                    expr = expr_el.text.strip() if expr_el is not None and expr_el.text else ""
                    result['virtual_bands'][bname] = expr
    except Exception as e:
        print(f"Error parsing DIMAP XML: {e}")

# 2. Check GeoTIFF Output
tif_file = "/home/ga/snap_exports/landsat_texture.tif"
if os.path.exists(tif_file):
    result['tif_found'] = True
    result['tif_file_size'] = os.path.getsize(tif_file)
    mtime = int(os.path.getmtime(tif_file))
    if mtime >= task_start:
        result['tif_created_after_start'] = True

# Write state to JSON
out_json = '/tmp/glcm_result.json'
with open(out_json, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result parsed and written to {out_json}")
PYEOF

echo "=== Export Complete ==="