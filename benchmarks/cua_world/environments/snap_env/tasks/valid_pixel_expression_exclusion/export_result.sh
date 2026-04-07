#!/bin/bash
echo "=== Exporting valid_pixel_expression_exclusion result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Extract data using a Python script safely
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    try:
        task_start = int(open('/tmp/task_start_ts').read().strip())
    except:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'ndvi_band_found': False,
    'ndvi_expression': '',
    'ndvi_valid_pixel_expression': ''
}

dim_file = '/home/ga/snap_exports/landsat_masked_ndvi.dim'
if os.path.exists(dim_file):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_file))
    if mtime > task_start:
        result['dim_created_after_start'] = True

    try:
        tree = ET.parse(dim_file)
        root = tree.getroot()
        
        # Traverse to find Spectral_Band_Info
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text and name_el.text.strip().lower() == 'ndvi':
                result['ndvi_band_found'] = True
                
                # Check all children for case-insensitive tags
                for child in sbi:
                    tag = child.tag.lower()
                    if tag == 'virtual_band_expression' and child.text:
                        result['ndvi_expression'] = child.text.strip()
                    elif tag == 'valid_pixel_expression' and child.text:
                        result['ndvi_valid_pixel_expression'] = child.text.strip()
                        
    except Exception as e:
        result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="