#!/bin/bash
echo "=== Exporting cross_sensor_datacube_collocation results ==="

# Take final state screenshot
DISPLAY=:1 scrot /tmp/collocation_task_end.png 2>/dev/null || true

# Run a Python script to deeply parse the SNAP DIMAP XML and file outputs
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

result = {
    'task_start': 0,
    'dim_found': False,
    'dim_created_after_start': False,
    'operator_collocate_found': False,
    'total_band_count': 0,
    'band_names': [],
    'renamed_band_found': False,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# 1. Read task start timestamp
ts_file = '/tmp/collocation_task_start_ts'
if os.path.exists(ts_file):
    try:
        with open(ts_file, 'r') as f:
            result['task_start'] = int(f.read().strip())
    except:
        pass

# 2. Check for the BEAM-DIMAP product
dim_path = '/home/ga/snap_projects/ml_datacube.dim'
if os.path.exists(dim_path):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime >= result['task_start'] and result['task_start'] > 0:
         result['dim_created_after_start'] = True
         
    # Parse the XML to verify processing graph and band definitions
    try:
        # Check processing lineage for "Collocate" to prevent UI bypass gaming
        with open(dim_path, 'r', encoding='utf-8') as f:
            content = f.read()
            if 'Collocate' in content or 'collocate' in content:
                result['operator_collocate_found'] = True
                
        # Parse XML tree to count bands and check for renamed band
        tree = ET.parse(dim_path)
        root = tree.getroot()
        
        for sbi in root.iter('Spectral_Band_Info'):
            result['total_band_count'] += 1
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['band_names'].append(bname)
                if bname == 'elevation_resampled':
                    result['renamed_band_found'] = True
                    
    except Exception as e:
        print(f"Error parsing DIMAP XML: {e}")

# 3. Check for the exported GeoTIFF
tif_path = '/home/ga/snap_exports/ml_datacube.tif'
if os.path.exists(tif_path):
    result['tif_found'] = True
    mtime = int(os.path.getmtime(tif_path))
    if mtime >= result['task_start'] and result['task_start'] > 0:
        result['tif_created_after_start'] = True
    result['tif_file_size'] = os.path.getsize(tif_path)

# Write results to JSON
out_path = '/tmp/collocation_result.json'
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2)
    
print(f"Exported verification data to {out_path}")
PYEOF

echo "=== Result Export Complete ==="