#!/bin/bash
echo "=== Exporting bsi_erosion_risk_mapping results ==="

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Run Python script to parse XML (.dim) and check files safely
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

result = {
    'task_start': 0,
    'dim_found': False,
    'dim_created_during_task': False,
    'tif_found': False,
    'tif_created_during_task': False,
    'tif_size_bytes': 0,
    'bands_found': [],
    'bsi_band_exists': False,
    'bsi_expression': '',
    'risk_band_exists': False,
    'risk_expression': ''
}

# Read start time
try:
    with open('/tmp/bsi_task_start_ts', 'r') as f:
        result['task_start'] = int(f.read().strip())
except Exception:
    pass

# Check for DIMAP file
dim_path = '/home/ga/snap_exports/erosion_risk.dim'
if not os.path.exists(dim_path):
    # Fallback to searching exports dir for any new dim
    for f in os.listdir('/home/ga/snap_exports'):
        if f.endswith('.dim'):
            dim_path = os.path.join('/home/ga/snap_exports', f)
            break

if os.path.exists(dim_path):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime >= result['task_start']:
        result['dim_created_during_task'] = True

    # Parse DIMAP XML to evaluate math logic
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        
        for sbi in root.iter('Spectral_Band_Info'):
            name_node = sbi.find('BAND_NAME')
            if name_node is not None and name_node.text:
                bname = name_node.text.strip()
                result['bands_found'].append(bname)
                
                bname_lower = bname.lower()
                expr_node = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = expr_node.text.strip() if (expr_node is not None and expr_node.text) else ''

                if 'bsi' in bname_lower or 'bare_soil' in bname_lower:
                    result['bsi_band_exists'] = True
                    result['bsi_expression'] = expr_text
                
                if 'risk' in bname_lower or 'erosion' in bname_lower or 'mask' in bname_lower:
                    result['risk_band_exists'] = True
                    result['risk_expression'] = expr_text
                    
    except Exception as e:
        print(f"Error parsing XML: {e}")

# Check for GeoTIFF file
tif_path = '/home/ga/snap_exports/erosion_risk.tif'
if not os.path.exists(tif_path):
    # Fallback to searching
    for f in os.listdir('/home/ga/snap_exports'):
        if f.lower().endswith(('.tif', '.tiff')):
            tif_path = os.path.join('/home/ga/snap_exports', f)
            break

if os.path.exists(tif_path):
    result['tif_found'] = True
    result['tif_size_bytes'] = os.path.getsize(tif_path)
    mtime = int(os.path.getmtime(tif_path))
    if mtime >= result['task_start']:
        result['tif_created_during_task'] = True

# Write result JSON
with open('/tmp/bsi_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export completed successfully.")
PYEOF

echo "=== Export script finished ==="