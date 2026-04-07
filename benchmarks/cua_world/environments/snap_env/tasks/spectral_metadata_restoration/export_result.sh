#!/bin/bash
echo "=== Exporting spectral_metadata_restoration results ==="

# 1. Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Extract metadata from the exported DIMAP file using Python
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Read task start timestamp
task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    with open('/tmp/task_start_ts', 'r') as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

dim_path = '/home/ga/snap_exports/landsat_restored_metadata.dim'

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_during_task': False,
    'bands': {}
}

if os.path.exists(dim_path):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_path))
    result['dim_created_during_task'] = mtime > task_start
    
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        
        # Iterate over all Spectral_Band_Info nodes in the DIMAP XML
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                
                wl_el = sbi.find('SPECTRAL_WAVELENGTH')
                unit_el = sbi.find('UNIT')
                ndvu_el = sbi.find('NO_DATA_VALUE_USED')
                ndv_el = sbi.find('NO_DATA_VALUE')
                
                result['bands'][bname] = {
                    'wavelength': wl_el.text.strip() if wl_el is not None and wl_el.text else None,
                    'unit': unit_el.text.strip() if unit_el is not None and unit_el.text else None,
                    'no_data_used': ndvu_el.text.strip().lower() == 'true' if ndvu_el is not None and ndvu_el.text else False,
                    'no_data_value': ndv_el.text.strip() if ndv_el is not None and ndv_el.text else None
                }
    except Exception as e:
        result['parse_error'] = str(e)

# Write to temp file safely
temp_out = '/tmp/spectral_metadata_result.tmp.json'
with open(temp_out, 'w') as f:
    json.dump(result, f, indent=2)

os.system(f'mv {temp_out} /tmp/spectral_metadata_result.json')
os.system('chmod 666 /tmp/spectral_metadata_result.json')
PYEOF

echo "Result JSON saved to /tmp/spectral_metadata_result.json"
cat /tmp/spectral_metadata_result.json

echo "=== Export complete ==="