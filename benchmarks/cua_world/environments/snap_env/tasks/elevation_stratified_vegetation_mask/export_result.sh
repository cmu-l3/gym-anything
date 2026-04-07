#!/bin/bash
echo "=== Exporting elevation_stratified_vegetation_mask result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    with open(ts_file) as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'band_names': [],
    'virtual_bands': {},
    'collocation_history': False,
    'has_ndvi_band': False,
    'has_mask_band': False,
    'ndvi_expression': '',
    'mask_expression': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# Search for DIMAP files
search_dirs = ['/home/ga/snap_projects', '/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga', '/tmp']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim') and 'snap_data' not in root:
                    dim_files.append(os.path.join(root, f))

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        # Check for collocation in history or source products
        source_count = 0
        for src in root.iter('Source_Product'):
            source_count += 1
        if source_count >= 2:
            result['collocation_history'] = True
            
        for hist in root.iter('Node_Id'):
            if 'Collocate' in (hist.text or ''):
                result['collocation_history'] = True

        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['band_names'].append(bname)

                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = ''
                if expr_el is not None and expr_el.text:
                    expr_text = expr_el.text.strip()
                    result['virtual_bands'][bname] = expr_text

                bl = bname.lower()
                if 'ndvi' in bl:
                    result['has_ndvi_band'] = True
                    if expr_text:
                        result['ndvi_expression'] = expr_text
                
                if 'mask' in bl or 'alpine' in bl or 'veg' in bl:
                    if 'ndvi' not in bl:
                        result['has_mask_band'] = True
                        if expr_text:
                            result['mask_expression'] = expr_text
                            
        # additional heuristic for collocation
        if any('_m' in b.lower() for b in result['band_names']) and any('_s' in b.lower() for b in result['band_names']):
            result['collocation_history'] = True

    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# If mask band wasn't explicitly named, look for mask expressions
if not result['has_mask_band']:
    for bname, expr in result['virtual_bands'].items():
        el = expr.lower()
        if ('and' in el or '&&' in el or '*' in el) and '>' in el:
            result['has_mask_band'] = True
            result['mask_expression'] = expr

# Search for GeoTIFF exports
tif_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
for d in tif_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.tif', '.tiff')):
                full = os.path.join(d, f)
                if 'snap_data' in full:
                    continue
                fsize = os.path.getsize(full)
                mtime = int(os.path.getmtime(full))
                if mtime > task_start and fsize > result['tif_file_size']:
                    # Prioritize correctly named files
                    if 'mask' in f.lower() or 'alpine' in f.lower() or 'veg' in f.lower():
                        result['tif_found'] = True
                        result['tif_created_after_start'] = True
                        result['tif_file_size'] = fsize
                    elif not result['tif_found']:
                        result['tif_found'] = True
                        result['tif_created_after_start'] = True
                        result['tif_file_size'] = fsize

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="