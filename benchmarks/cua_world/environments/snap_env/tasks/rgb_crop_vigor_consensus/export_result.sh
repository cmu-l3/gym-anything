#!/bin/bash
echo "=== Exporting rgb_crop_vigor_consensus result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/rgb_crop_vigor_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/rgb_crop_vigor_end_screenshot.png 2>/dev/null || true

# Parse dimensions and export results using Python
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/rgb_crop_vigor_start_ts'
if os.path.exists(ts_file):
    try:
        task_start = int(open(ts_file).read().strip())
    except:
        pass

result = {
    'task_start': task_start,
    'dimap_found': False,
    'dimap_created_after_start': False,
    'band_names': [],
    'virtual_bands': {},
    'envi_hdr_found': False,
    'envi_created_after_start': False,
    'envi_file_size': 0
}

# 1. Search for the saved BEAM-DIMAP project
search_dirs = ['/home/ga/snap_projects', '/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga']
dim_file_path = None

for d in search_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith('.dim') and 'rgb_vigor' in f.lower():
                dim_file_path = os.path.join(d, f)
                break
        if dim_file_path:
            break

# Fallback: find any .dim file created after start
if not dim_file_path:
    for d in search_dirs:
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith('.dim'):
                    fp = os.path.join(d, f)
                    if os.path.getmtime(fp) > task_start:
                        dim_file_path = fp
                        break
            if dim_file_path:
                break

if dim_file_path:
    result['dimap_found'] = True
    if os.path.getmtime(dim_file_path) > task_start:
        result['dimap_created_after_start'] = True
    
    # Parse XML to find derived bands
    try:
        tree = ET.parse(dim_file_path)
        root = tree.getroot()
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['band_names'].append(bname)
                
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                if expr_el is not None and expr_el.text:
                    result['virtual_bands'][bname] = expr_el.text.strip()
    except Exception as e:
        print(f"Error parsing DIMAP XML {dim_file_path}: {e}")

# 2. Search for the ENVI export
envi_hdr_path = None
envi_data_path = None

for d in search_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith('.hdr') and 'rgb_vigor' in f.lower():
                envi_hdr_path = os.path.join(d, f)
                base_name = f[:-4]
                # ENVI data files might have .img, .dat, or no extension
                for ext in ['.img', '.dat', '']:
                    dp = os.path.join(d, base_name + ext)
                    if os.path.isfile(dp) and dp != envi_hdr_path:
                        envi_data_path = dp
                        break
                break
        if envi_hdr_path:
            break

if envi_hdr_path:
    result['envi_hdr_found'] = True
    if os.path.getmtime(envi_hdr_path) > task_start:
        result['envi_created_after_start'] = True
    
    if envi_data_path:
        result['envi_file_size'] = os.path.getsize(envi_data_path)
    else:
        result['envi_file_size'] = os.path.getsize(envi_hdr_path)

with open('/tmp/rgb_crop_vigor_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export data gathered successfully:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="