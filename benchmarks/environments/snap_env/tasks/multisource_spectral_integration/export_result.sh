#!/bin/bash
echo "=== Exporting multisource_spectral_integration result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/multisource_spectral_integration_end_screenshot.png

python3 << 'PYEOF'
import os, json, xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/multisource_spectral_integration_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'band_names': [],
    'virtual_bands': {},
    'total_band_count': 0,
    'has_multisource_bands': False,
    'source_band_count': 0,
    'has_derived_index': False,
    'derived_index_expression': '',
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

# Track bands from each source to detect collocation
red_keywords = ['red', 'b04', 'b4', 'sentinel2_b04']
nir_keywords = ['nir', 'b08', 'b8', 'sentinel2_b08']
index_keywords = ['ndvi', 'vegetation', 'index', 'vi', 'savi', 'evi', 'ratio']

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        file_bands = []
        has_red_source = False
        has_nir_source = False

        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                file_bands.append(bname)
                result['band_names'].append(bname)
                result['total_band_count'] += 1

                bl = bname.lower()

                # Check if this band comes from the red source
                if any(kw in bl for kw in red_keywords):
                    has_red_source = True
                # Check if this band comes from the NIR source
                if any(kw in bl for kw in nir_keywords):
                    has_nir_source = True

                # Check for derived index bands
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = ''
                if expr_el is not None and expr_el.text:
                    expr_text = expr_el.text.strip()
                    result['virtual_bands'][bname] = expr_text

                if any(kw in bl for kw in index_keywords):
                    result['has_derived_index'] = True
                    if expr_text:
                        result['derived_index_expression'] = expr_text

        # A product with 2+ non-virtual bands likely has both sources
        non_virtual_count = sum(1 for b in file_bands
                                if b not in result.get('virtual_bands', {}))
        if non_virtual_count >= 2:
            result['source_band_count'] = non_virtual_count

        # If product has bands referencing both source names, it's multi-source
        if has_red_source and has_nir_source:
            result['has_multisource_bands'] = True
        elif len(file_bands) >= 2:
            # Collocated products may just have generic band names
            # Check if virtual band expressions reference multiple bands
            for expr in result.get('virtual_bands', {}).values():
                el = expr.lower()
                refs = sum(1 for kw in ['band_1', 'band_2', 'b04', 'b08',
                                        '$4', '$8', 'red', 'nir']
                           if kw in el)
                if refs >= 2:
                    result['has_multisource_bands'] = True
                    break
            if non_virtual_count >= 2:
                result['has_multisource_bands'] = True

        # Check virtual bands for index-like expressions
        if not result['has_derived_index']:
            for bname, expr in result.get('virtual_bands', {}).items():
                el = expr.lower().replace(' ', '')
                # Normalized difference pattern: (A-B)/(A+B)
                if '/' in el and ('+' in el or '-' in el):
                    result['has_derived_index'] = True
                    result['derived_index_expression'] = expr
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

with open('/tmp/multisource_spectral_integration_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/multisource_spectral_integration_result.json")
PYEOF

echo "=== Export Complete ==="
