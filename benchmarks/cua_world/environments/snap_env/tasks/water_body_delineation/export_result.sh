#!/bin/bash
echo "=== Exporting water_body_delineation result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/water_body_delineation_end_screenshot.png

python3 << 'PYEOF'
import os, json, xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/water_body_delineation_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'band_names': [],
    'virtual_bands': {},
    'total_band_count': 0,
    'has_ndwi': False,
    'has_mndwi': False,
    'has_water_mask': False,
    'has_water_confidence': False,
    'ndwi_expression': '',
    'mndwi_expression': '',
    'water_mask_expression': '',
    'water_confidence_expression': '',
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

# Keywords for water-related bands
ndwi_keywords = ['ndwi']
mndwi_keywords = ['mndwi', 'modified_ndwi', 'mod_ndwi', 'modified_water']
water_mask_keywords = ['mask', 'water_mask', 'binary', 'waterbody', 'water_body']
water_conf_keywords = ['confidence', 'combined', 'composite', 'fusion', 'multi_index',
                       'water_conf', 'water_score', 'evidence']
# Also detect generic water index names
any_water_keywords = ['water', 'ndwi', 'mndwi', 'aqua', 'hydro']

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        water_index_bands = []

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

                # Detect NDWI (Green-NIR)/(Green+NIR) = (band_4-band_2)/(band_4+band_2)
                if any(kw in bl for kw in ndwi_keywords) and not any(kw in bl for kw in mndwi_keywords):
                    result['has_ndwi'] = True
                    if expr_text:
                        result['ndwi_expression'] = expr_text

                # Detect MNDWI (Green-SWIR)/(Green+SWIR) = (band_4-band_1)/(band_4+band_1)
                if any(kw in bl for kw in mndwi_keywords):
                    result['has_mndwi'] = True
                    if expr_text:
                        result['mndwi_expression'] = expr_text

                # Detect water mask (binary classification)
                if any(kw in bl for kw in water_mask_keywords):
                    result['has_water_mask'] = True
                    if expr_text:
                        result['water_mask_expression'] = expr_text

                # Detect water confidence / combined index
                if any(kw in bl for kw in water_conf_keywords):
                    result['has_water_confidence'] = True
                    if expr_text:
                        result['water_confidence_expression'] = expr_text

                # Track any water-related band
                if any(kw in bl for kw in any_water_keywords):
                    water_index_bands.append(bname)

        # Fallback detection via expression analysis
        for bname, expr in result.get('virtual_bands', {}).items():
            el = expr.lower().replace(' ', '')

            # Detect NDWI by expression pattern: (band_4-band_2)/(band_4+band_2)
            if not result['has_ndwi']:
                if ('band_4' in el or 'green' in el) and ('band_2' in el or 'nir' in el):
                    if '/' in el and '-' in el and '+' in el:
                        if 'band_1' not in el and 'swir' not in el:
                            result['has_ndwi'] = True
                            result['ndwi_expression'] = expr

            # Detect MNDWI by expression pattern: (band_4-band_1)/(band_4+band_1)
            if not result['has_mndwi']:
                if ('band_4' in el or 'green' in el) and ('band_1' in el or 'swir' in el):
                    if '/' in el and '-' in el and '+' in el:
                        result['has_mndwi'] = True
                        result['mndwi_expression'] = expr

            # Detect water mask by threshold expression
            if not result['has_water_mask']:
                if ('if(' in el or '?' in el or '>' in el) and \
                   any(kw in el for kw in ['ndwi', 'water', 'band_4', 'green']):
                    result['has_water_mask'] = True
                    result['water_mask_expression'] = expr

            # Detect combined water confidence
            if not result['has_water_confidence']:
                # Look for expressions combining two water indices
                if (('ndwi' in el and 'mndwi' in el) or
                    (el.count('+') >= 1 and el.count('/') >= 1 and
                     any(kw in el for kw in ['ndwi', 'mndwi', 'water']))):
                    result['has_water_confidence'] = True
                    result['water_confidence_expression'] = expr

        # If we found 2+ water-related bands but didn't distinguish them
        if len(water_index_bands) >= 2 and not result['has_mndwi']:
            # Mark as having second water index
            result['has_mndwi'] = True

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

with open('/tmp/water_body_delineation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/water_body_delineation_result.json")
PYEOF

echo "=== Export Complete ==="
