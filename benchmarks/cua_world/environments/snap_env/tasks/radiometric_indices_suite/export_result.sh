#!/bin/bash
echo "=== Exporting radiometric_indices_suite result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/radiometric_indices_suite_end_screenshot.png

python3 << 'PYEOF'
import os, json, re, xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/radiometric_indices_suite_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'band_names': [],
    'virtual_bands': {},
    'total_band_count': 0,
    'has_ndvi': False,
    'has_ndwi': False,
    'has_savi': False,
    'has_bsi': False,
    'additional_index_count': 0,
    'ndvi_expression': '',
    'ndwi_expression': '',
    'savi_expression': '',
    'bsi_expression': '',
    'has_classification_band': False,
    'classification_expression': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# Search for .dim files
search_dirs = ['/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']
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

# Keywords for each index type
ndvi_keywords = ['ndvi', 'vegetation_index', 'veg_index']
ndwi_keywords = ['ndwi', 'water_index', 'mndwi']
savi_keywords = ['savi', 'soil_adj', 'soil_vegetation']
bsi_keywords = ['bsi', 'bare_soil', 'soil_index', 'bareness']
class_keywords = ['class', 'cover', 'land_cover', 'landcover', 'categ', 'type', 'zone']
# Other possible indices the agent might create
extra_index_keywords = ['nbr', 'evi', 'arvi', 'gndvi', 'ratio', 'brightness',
                        'greenness', 'wetness', 'ndbi', 'built']

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
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

                if any(kw in bl for kw in ndvi_keywords):
                    result['has_ndvi'] = True
                    if expr_text:
                        result['ndvi_expression'] = expr_text

                if any(kw in bl for kw in ndwi_keywords):
                    result['has_ndwi'] = True
                    if expr_text:
                        result['ndwi_expression'] = expr_text

                if any(kw in bl for kw in savi_keywords):
                    result['has_savi'] = True
                    if expr_text:
                        result['savi_expression'] = expr_text

                if any(kw in bl for kw in bsi_keywords):
                    result['has_bsi'] = True
                    if expr_text:
                        result['bsi_expression'] = expr_text

                if any(kw in bl for kw in class_keywords):
                    result['has_classification_band'] = True
                    if expr_text:
                        result['classification_expression'] = expr_text

                if any(kw in bl for kw in extra_index_keywords):
                    result['additional_index_count'] += 1

        # Fallback: check for unnamed index bands via expression patterns
        if not result['has_ndvi']:
            for bname, expr in result.get('virtual_bands', {}).items():
                el = expr.lower().replace(' ', '')
                # NDVI pattern: (NIR-Red)/(NIR+Red) using band_2 and band_3
                if ('band_2' in el or 'nir' in el) and ('band_3' in el or 'red' in el):
                    if '/' in el and '-' in el and '+' in el:
                        result['has_ndvi'] = True
                        result['ndvi_expression'] = expr
                        break

        if not result['has_ndwi']:
            for bname, expr in result.get('virtual_bands', {}).items():
                el = expr.lower().replace(' ', '')
                # NDWI pattern: (Green-NIR)/(Green+NIR) using band_4 and band_2
                if ('band_4' in el or 'green' in el) and ('band_2' in el or 'nir' in el):
                    if '/' in el and '-' in el and '+' in el:
                        result['has_ndwi'] = True
                        result['ndwi_expression'] = expr
                        break

        if not result['has_classification_band']:
            for bname, expr in result.get('virtual_bands', {}).items():
                el = expr.lower().replace(' ', '')
                if 'if(' in el or 'if (' in el or '?' in el:
                    result['has_classification_band'] = True
                    result['classification_expression'] = expr
                    break

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
                if mtime > task_start and fsize > result['tif_file_size']:
                    result['tif_found'] = True
                    result['tif_created_after_start'] = True
                    result['tif_file_size'] = fsize

with open('/tmp/radiometric_indices_suite_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/radiometric_indices_suite_result.json")
PYEOF

echo "=== Export Complete ==="
