#!/bin/bash
echo "=== Exporting fvc_empirical_modeling result ==="

# Take final state screenshot
DISPLAY=:1 scrot /tmp/fvc_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/fvc_end_screenshot.png 2>/dev/null || true

# Run Python script inside the container to safely parse the XML and file metadata
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
if os.path.exists('/tmp/fvc_start_ts'):
    try:
        task_start = int(open('/tmp/fvc_start_ts').read().strip())
    except:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'bands': {},
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_size': 0
}

dim_path = '/home/ga/snap_exports/landsat_fvc.dim'
if os.path.exists(dim_path):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime >= task_start:
        result['dim_created_after_start'] = True
        
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr = expr_el.text.strip() if expr_el is not None and expr_el.text else ""
                result['bands'][bname] = expr
    except Exception as e:
        result['xml_error'] = str(e)

tif_path = '/home/ga/snap_exports/fvc_map.tif'
if os.path.exists(tif_path):
    result['tif_found'] = True
    mtime = int(os.path.getmtime(tif_path))
    if mtime >= task_start:
        result['tif_created_after_start'] = True
    result['tif_size'] = os.path.getsize(tif_path)

# Fallback: check if they saved it elsewhere in snap_exports
if not result['dim_found'] or not result['tif_found']:
    for f in os.listdir('/home/ga/snap_exports'):
        full_path = os.path.join('/home/ga/snap_exports', f)
        if f.endswith('.dim') and not result['dim_found']:
            result['dim_found'] = True
            if int(os.path.getmtime(full_path)) >= task_start:
                result['dim_created_after_start'] = True
            # Parse fallback XML
            try:
                tree = ET.parse(full_path)
                for sbi in tree.getroot().iter('Spectral_Band_Info'):
                    name_el = sbi.find('BAND_NAME')
                    if name_el is not None and name_el.text:
                        result['bands'][name_el.text.strip()] = sbi.find('VIRTUAL_BAND_EXPRESSION').text or ""
            except:
                pass
        if f.lower().endswith(('.tif', '.tiff')) and not result['tif_found']:
            result['tif_found'] = True
            if int(os.path.getmtime(full_path)) >= task_start:
                result['tif_created_after_start'] = True
            result['tif_size'] = os.path.getsize(full_path)

with open('/tmp/fvc_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/fvc_result.json 2>/dev/null || true
echo "Result exported to /tmp/fvc_result.json"
cat /tmp/fvc_result.json