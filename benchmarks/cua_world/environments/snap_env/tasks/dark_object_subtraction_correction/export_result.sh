#!/bin/bash
echo "=== Exporting dark_object_subtraction_correction result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/dos_correction_end_screenshot.png 2>/dev/null || true

# Extract data using a python script
cat << 'PYEOF' > /tmp/parse_dos_dimap.py
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/dos_correction_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'band_names': [],
    'virtual_bands': {},
    'total_band_count': 0,
    'has_red_corrected': False,
    'has_green_corrected': False,
    'red_expression': '',
    'green_expression': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# Search for .dim files in the specified exports directory (and fallback to projects/home)
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim'):
                    full = os.path.join(root, f)
                    if 'snap_data' in full:
                        continue
                    dim_files.append(full)

red_keywords = ['red', 'band_3', 'band3']
green_keywords = ['green', 'band_4', 'band4']
corr_keywords = ['corr', 'dos', 'sub', 'atm']

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime >= task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['band_names'].append(bname)
                result['total_band_count'] += 1

                bl = bname.lower()
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = ''
                if expr_el is not None and expr_el.text:
                    expr_text = expr_el.text.strip()
                    result['virtual_bands'][bname] = expr_text

                # Check for corrected Red band
                if any(kw in bl for kw in red_keywords) and any(kw in bl for kw in corr_keywords):
                    result['has_red_corrected'] = True
                    if expr_text:
                        result['red_expression'] = expr_text

                # Check for corrected Green band
                if any(kw in bl for kw in green_keywords) and any(kw in bl for kw in corr_keywords):
                    result['has_green_corrected'] = True
                    if expr_text:
                        result['green_expression'] = expr_text

                # Fallback: if they just named it "dos_band" but it references band_3 inside
                if not result['has_red_corrected'] and expr_text and 'band_3' in expr_text.lower():
                    result['has_red_corrected'] = True
                    result['red_expression'] = expr_text

                if not result['has_green_corrected'] and expr_text and 'band_4' in expr_text.lower():
                    result['has_green_corrected'] = True
                    result['green_expression'] = expr_text

    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# Search for GeoTIFF exports
tif_dirs = ['/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga']
for d in tif_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.tif', '.tiff')):
                full = os.path.join(d, f)
                if 'snap_data' in full:
                    continue
                fsize = os.path.getsize(full)
                mtime = int(os.path.getmtime(full))
                if mtime >= task_start and fsize > result['tif_file_size']:
                    result['tif_found'] = True
                    result['tif_created_after_start'] = True
                    result['tif_file_size'] = fsize

with open('/tmp/dos_correction_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/dos_correction_result.json")
PYEOF

python3 /tmp/parse_dos_dimap.py

echo "=== Export Complete ==="