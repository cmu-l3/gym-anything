#!/bin/bash
echo "=== Exporting vegetation_density_slicing result ==="

# Take final screenshot as evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract task state and DIMAP metadata securely using Python
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
if os.path.exists('/tmp/task_start_time.txt'):
    with open('/tmp/task_start_time.txt') as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_size_bytes': 0,
    'expressions': [],
    'band_names': []
}

dim_path = '/home/ga/snap_projects/vegetation_zones.dim'
if os.path.exists(dim_path):
    result['dim_found'] = True
    if os.path.getmtime(dim_path) > task_start:
        result['dim_created_after_start'] = True

    try:
        # DIMAP metadata is XML, which contains the exact Band Maths formulas the user typed
        tree = ET.parse(dim_path)
        for sbi in tree.getroot().iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                result['band_names'].append(name_el.text)
            
            expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
            if expr_el is not None and expr_el.text:
                result['expressions'].append(expr_el.text)
    except Exception as e:
        print(f"Error parsing XML: {e}")

tif_path = '/home/ga/snap_exports/vegetation_zones.tif'
if os.path.exists(tif_path):
    result['tif_found'] = True
    result['tif_size_bytes'] = os.path.getsize(tif_path)
    if os.path.getmtime(tif_path) > task_start:
        result['tif_created_after_start'] = True

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported JSON Result:")
print(json.dumps(result, indent=2))
PYEOF

# Ensure verifier script can access the exported file
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="