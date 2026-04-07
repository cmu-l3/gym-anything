#!/bin/bash
echo "=== Exporting CMYK Conversion Results ==="

# 1. Take a screenshot of the final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract SNAP states and output file information via Python
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Read start time
task_start = 0
try:
    with open('/tmp/task_start_ts', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_mtime': 0,
    'dim_created_after_start': False,
    'band_names': [],
    'expressions': {},
    'tif_found': False,
    'tif_mtime': 0,
    'tif_created_after_start': False,
    'tif_size_bytes': 0
}

dim_path = '/home/ga/snap_exports/cmyk_print_ready.dim'
tif_path = '/home/ga/snap_exports/cmyk_print_ready.tif'

# Check DIMAP product
if os.path.exists(dim_path):
    result['dim_found'] = True
    result['dim_mtime'] = int(os.path.getmtime(dim_path))
    result['dim_created_after_start'] = result['dim_mtime'] >= task_start
    
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        
        # Parse all bands and their underlying mathematical expressions
        for sbi in root.iter('Spectral_Band_Info'):
            bname_el = sbi.find('BAND_NAME')
            bname = bname_el.text.strip() if bname_el is not None and bname_el.text else None
            
            if bname:
                result['band_names'].append(bname)
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                if expr_el is not None and expr_el.text:
                    result['expressions'][bname] = expr_el.text.strip()
    except Exception as e:
        result['dim_parse_error'] = str(e)

# Check GeoTIFF product
if os.path.exists(tif_path):
    result['tif_found'] = True
    result['tif_mtime'] = int(os.path.getmtime(tif_path))
    result['tif_created_after_start'] = result['tif_mtime'] >= task_start
    result['tif_size_bytes'] = os.path.getsize(tif_path)

# Write to standardized output JSON
output_json = '/tmp/cmyk_conversion_result.json'
with open(output_json, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result written to {output_json}")
PYEOF

chmod 666 /tmp/cmyk_conversion_result.json 2>/dev/null || true
echo "=== Export Complete ==="