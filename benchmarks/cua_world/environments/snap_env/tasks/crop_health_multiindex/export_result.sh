#!/bin/bash
echo "=== Exporting crop_health_multiindex result ==="

# Take final screenshot for visual verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to extract structured metadata from the created DIMAP and TIFF files
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
if os.path.exists('/tmp/crop_health_start_ts'):
    with open('/tmp/crop_health_start_ts', 'r') as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'total_bands': 0,
    'band_names': [],
    'virtual_bands': {},
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_size': 0
}

# Directories to search (in case agent saved it somewhere other than snap_exports)
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']

# 1. Find the best/largest DIMAP product
best_dim = None
max_bands = -1

for d in search_dirs:
    if os.path.exists(d):
        for root, _, files in os.walk(d):
            if 'snap_data' in root: continue  # Ignore the source files
            for f in files:
                if f.endswith('.dim'):
                    dim_path = os.path.join(root, f)
                    try:
                        tree = ET.parse(dim_path)
                        bands = list(tree.getroot().iter('Spectral_Band_Info'))
                        if len(bands) > max_bands:
                            max_bands = len(bands)
                            best_dim = dim_path
                    except Exception:
                        pass

if best_dim:
    result['dim_found'] = True
    if int(os.path.getmtime(best_dim)) > task_start:
        result['dim_created_after_start'] = True
    
    try:
        tree = ET.parse(best_dim)
        root = tree.getroot()
        for sbi in root.iter('Spectral_Band_Info'):
            result['total_bands'] += 1
            name_el = sbi.find('BAND_NAME')
            expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
            
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['band_names'].append(bname)
                
                # Capture the band math formula if it was saved virtually
                if expr_el is not None and expr_el.text:
                    result['virtual_bands'][bname] = expr_el.text.strip()
    except Exception as e:
        print(f"Error parsing dim XML: {e}")

# 2. Find the best GeoTIFF export
best_tif = None
max_size = -1

for d in search_dirs:
    if os.path.exists(d):
        for root, _, files in os.walk(d):
            if 'snap_data' in root: continue
            for f in files:
                if f.lower().endswith(('.tif', '.tiff')):
                    tif_path = os.path.join(root, f)
                    sz = os.path.getsize(tif_path)
                    if sz > max_size:
                        max_size = sz
                        best_tif = tif_path

if best_tif:
    result['tif_found'] = True
    if int(os.path.getmtime(best_tif)) > task_start:
        result['tif_created_after_start'] = True
    result['tif_size'] = max_size

# Save parsed payload for the host verifier
with open('/tmp/crop_health_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/crop_health_result.json 2>/dev/null || true
echo "Export complete. Payload results:"
cat /tmp/crop_health_result.json