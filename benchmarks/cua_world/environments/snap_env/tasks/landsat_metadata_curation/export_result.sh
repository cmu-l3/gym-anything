#!/bin/bash
echo "=== Exporting landsat_metadata_curation result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract DIMAP metadata using Python
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
try:
    with open('/tmp/task_start_ts') as f:
        task_start = int(f.read().strip())
except:
    pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'bands': []
}

dim_file = '/home/ga/snap_exports/curated_landsat.dim'
if os.path.exists(dim_file):
    mtime = int(os.path.getmtime(dim_file))
    result['dim_found'] = True
    if mtime > task_start:
        result['dim_created_after_start'] = True
    
    try:
        tree = ET.parse(dim_file)
        root = tree.getroot()
        
        for sbi in root.iter('Spectral_Band_Info'):
            band_info = {}
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                band_info['name'] = name_el.text.strip()
            
            unit_el = sbi.find('UNIT')
            if unit_el is not None and unit_el.text:
                band_info['unit'] = unit_el.text.strip()
                
            nd_used_el = sbi.find('NO_DATA_VALUE_USED')
            if nd_used_el is not None and nd_used_el.text:
                band_info['no_data_used'] = nd_used_el.text.strip().lower() == 'true'
                
            nd_val_el = sbi.find('NO_DATA_VALUE')
            if nd_val_el is not None and nd_val_el.text:
                try:
                    band_info['no_data_value'] = float(nd_val_el.text.strip())
                except:
                    band_info['no_data_value'] = nd_val_el.text.strip()
            
            result['bands'].append(band_info)
    except Exception as e:
        result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="