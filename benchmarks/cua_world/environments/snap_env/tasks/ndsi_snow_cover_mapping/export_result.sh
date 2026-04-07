#!/bin/bash
echo "=== Exporting ndsi_snow_cover_mapping result ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import os, json
import xml.etree.ElementTree as ET

task_start = 0
if os.path.exists('/tmp/task_start_time.txt'):
    task_start = int(open('/tmp/task_start_time.txt').read().strip())

result = {
    'task_start': task_start,
    'dim_exists': False,
    'dim_created_during_task': False,
    'ndsi_band_exists': False,
    'ndsi_expression': '',
    'mask_band_exists': False,
    'mask_expression': '',
    'tif_exists': False,
    'tif_created_during_task': False,
    'tif_size_bytes': 0
}

# 1. Check for DIMAP file
dim_path = '/home/ga/snap_projects/snow_mapping.dim'
if not os.path.exists(dim_path):
    # Fallback: find any .dim file in projects directory
    if os.path.exists('/home/ga/snap_projects'):
        for f in os.listdir('/home/ga/snap_projects'):
            if f.endswith('.dim'):
                dim_path = os.path.join('/home/ga/snap_projects', f)
                break

if os.path.exists(dim_path) and dim_path.endswith('.dim'):
    result['dim_exists'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime > task_start:
        result['dim_created_during_task'] = True
    
    # Parse XML to find bands and expressions
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip().lower()
                
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = ''
                if expr_el is not None and expr_el.text:
                    expr_text = expr_el.text.strip()
                
                if 'ndsi' in bname:
                    result['ndsi_band_exists'] = True
                    if expr_text:
                        result['ndsi_expression'] = expr_text
                elif 'mask' in bname or 'snow' in bname:
                    result['mask_band_exists'] = True
                    if expr_text:
                        result['mask_expression'] = expr_text
                            
    except Exception as e:
        print(f"Error parsing {dim_path}: {e}")

# 2. Check for GeoTIFF file
tif_path = '/home/ga/snap_exports/snow_mapping.tif'
if not os.path.exists(tif_path):
    # Fallback: find any .tif file in exports directory
    if os.path.exists('/home/ga/snap_exports'):
        for f in os.listdir('/home/ga/snap_exports'):
            if f.endswith('.tif'):
                tif_path = os.path.join('/home/ga/snap_exports', f)
                break

if os.path.exists(tif_path) and tif_path.endswith('.tif'):
    result['tif_exists'] = True
    mtime = int(os.path.getmtime(tif_path))
    if mtime > task_start:
        result['tif_created_during_task'] = True
    result['tif_size_bytes'] = os.path.getsize(tif_path)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json
echo "=== Export Complete ==="