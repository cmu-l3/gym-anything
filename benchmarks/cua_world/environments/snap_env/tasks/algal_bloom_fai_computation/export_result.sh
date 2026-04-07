#!/bin/bash
echo "=== Exporting algal_bloom_fai_computation result ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Run a Python script to parse the output files safely and write to JSON
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    try:
        task_start = int(open(ts_file).read().strip())
    except:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'bands': [],
    'ndwi_found': False,
    'ndwi_expression': '',
    'fai_found': False,
    'fai_expression': '',
    'fai_valid_pixel_expression': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# 1. Search for BEAM-DIMAP (.dim) file
dim_target = '/home/ga/snap_exports/algal_bloom_fai.dim'
dim_files = [dim_target] if os.path.exists(dim_target) else []

# Fallback search if exact path missed
if not dim_files:
    for d in ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga']:
        if os.path.exists(d):
            for f in os.listdir(d):
                if f.endswith('.dim') and 'algal' in f.lower():
                    dim_files.append(os.path.join(d, f))

if dim_files:
    best_dim = dim_files[0]
    result['dim_found'] = True
    mtime = int(os.path.getmtime(best_dim))
    if mtime > task_start:
        result['dim_created_after_start'] = True
    
    try:
        tree = ET.parse(best_dim)
        root = tree.getroot()
        
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['bands'].append(bname)
                
                # Check for Virtual Expression (Band Math)
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = expr_el.text.strip() if (expr_el is not None and expr_el.text) else ''
                
                # Check for Valid Pixel Expression
                vpe_el = sbi.find('VALID_PIXEL_EXPRESSION')
                vpe_text = vpe_el.text.strip() if (vpe_el is not None and vpe_el.text) else ''

                # Identify NDWI
                if bname.upper() == 'NDWI' or 'NDWI' in bname.upper():
                    result['ndwi_found'] = True
                    result['ndwi_expression'] = expr_text
                
                # Identify FAI
                if bname.upper() == 'FAI' or 'FAI' in bname.upper():
                    result['fai_found'] = True
                    result['fai_expression'] = expr_text
                    result['fai_valid_pixel_expression'] = vpe_text

    except Exception as e:
        print(f"Error parsing DIMAP XML: {e}")

# 2. Search for GeoTIFF (.tif) file
tif_target = '/home/ga/snap_exports/algal_bloom_fai.tif'
tif_files = [tif_target] if os.path.exists(tif_target) else []

# Fallback search
if not tif_files:
    for d in ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga']:
        if os.path.exists(d):
            for f in os.listdir(d):
                if f.endswith('.tif') and 'algal' in f.lower():
                    tif_files.append(os.path.join(d, f))

if tif_files:
    best_tif = tif_files[0]
    result['tif_found'] = True
    mtime = int(os.path.getmtime(best_tif))
    if mtime > task_start:
        result['tif_created_after_start'] = True
    result['tif_file_size'] = os.path.getsize(best_tif)

# Save result to tmp for verifier
with open('/tmp/algal_bloom_fai_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export data gathered successfully.")
PYEOF

echo "=== Export Complete ==="