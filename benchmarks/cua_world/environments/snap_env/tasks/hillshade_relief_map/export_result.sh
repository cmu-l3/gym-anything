#!/bin/bash
echo "=== Exporting hillshade_relief_map result ==="

# Take final screenshot showing end state
DISPLAY=:1 scrot /tmp/hillshade_task_end.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/hillshade_task_end.png 2>/dev/null || true

python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/hillshade_task_start_ts'
if os.path.exists(ts_file):
    try:
        task_start = int(open(ts_file).read().strip())
    except Exception:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'dim_file_path': '',
    'band_names': [],
    'virtual_bands': {},
    'total_band_count': 0,
    'has_gradient_bands': False,
    'gradient_band_count': 0,
    'has_slope_band': False,
    'has_aspect_band': False,
    'has_hillshade_band': False,
    'slope_expression': '',
    'aspect_expression': '',
    'hillshade_expression': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_path': '',
    'tif_file_size': 0
}

# Find all saved BEAM-DIMAP products (.dim)
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']
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

grad_keywords = ['dx', 'dy', 'grad', 'edge', 'sobel', 'diff', 'x', 'y']
slope_keywords = ['slope', 'steep']
aspect_keywords = ['aspect', 'azimuth']
hillshade_keywords = ['hill', 'shade', 'relief', 'illum']

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        
        result['dim_found'] = True
        result['dim_file_path'] = dim_file

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

                # Check for Gradients
                if any(kw in bl for kw in grad_keywords) or ('dx' in expr_text.lower() or 'dy' in expr_text.lower()):
                    result['gradient_band_count'] += 1

                # Check for Slope
                if any(kw in bl for kw in slope_keywords) or ('atan' in expr_text.lower() and 'sqrt' in expr_text.lower()):
                    result['has_slope_band'] = True
                    if expr_text:
                        result['slope_expression'] = expr_text

                # Check for Aspect
                if any(kw in bl for kw in aspect_keywords) or ('atan2' in expr_text.lower()):
                    result['has_aspect_band'] = True
                    if expr_text:
                        result['aspect_expression'] = expr_text

                # Check for Hillshade
                if any(kw in bl for kw in hillshade_keywords) or ('cos' in expr_text.lower() and 'sin' in expr_text.lower()):
                    result['has_hillshade_band'] = True
                    if expr_text:
                        result['hillshade_expression'] = expr_text

        if result['gradient_band_count'] >= 2:
            result['has_gradient_bands'] = True
            
        # Break if we hit a product that represents the final output (with hillshade)
        if result['has_hillshade_band']:
            break

    except Exception as e:
        print(f"Error parsing DIMAP {dim_file}: {e}")

# Search for GeoTIFF exports
tif_dirs = ['/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga']
for d in tif_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.tif', '.tiff')):
                full = os.path.join(d, f)
                # Ignore initial input files
                if 'snap_data' in full:
                    continue
                
                fsize = os.path.getsize(full)
                mtime = int(os.path.getmtime(full))
                
                # Identify the most recent or largest TIFF that was created
                if mtime > task_start and fsize > result['tif_file_size']:
                    result['tif_found'] = True
                    result['tif_created_after_start'] = True
                    result['tif_file_size'] = fsize
                    result['tif_file_path'] = full

with open('/tmp/hillshade_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Results compiled and written to /tmp/hillshade_result.json")
PYEOF

echo "=== Export Complete ==="