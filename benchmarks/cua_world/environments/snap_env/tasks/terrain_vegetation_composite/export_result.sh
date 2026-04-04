#!/bin/bash
echo "=== Exporting terrain_vegetation_composite result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/terrain_vegetation_composite_end_screenshot.png

python3 << 'PYEOF'
import os, json, xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/terrain_vegetation_composite_start_ts'
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
    'has_dem_band': False,
    'has_optical_bands': False,
    'has_vegetation_index': False,
    'has_terrain_metric': False,
    'has_composite': False,
    'has_suitability_class': False,
    'vegetation_expression': '',
    'terrain_expression': '',
    'composite_expression': '',
    'suitability_expression': '',
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

# Keywords
dem_keywords = ['elevation', 'dem', 'srtm', 'height', 'altitude', 'band_1']
optical_keywords = ['band_2', 'band_3', 'band_4', 'nir', 'red', 'green', 'swir',
                     'b04', 'b08', 'b03', 'b02']
veg_keywords = ['ndvi', 'vegetation', 'veg_index', 'greenness', 'vi']
terrain_keywords = ['slope', 'gradient', 'steep', 'aspect', 'terrain_steep',
                    'incline', 'terrain_metric']
composite_keywords = ['composite', 'combined', 'integrated', 'fusion',
                      'terrain_veg', 'veg_terrain', 'harvest', 'suitability_score']
suit_keywords = ['suitability', 'suitable', 'class', 'zone', 'categ',
                 'harvest_class', 'forest_class', 'rating']

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        file_has_dem = False
        file_has_optical = False

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

                # Check for DEM-derived bands
                if any(kw in bl for kw in dem_keywords):
                    file_has_dem = True
                    result['has_dem_band'] = True

                # Check for optical bands
                if any(kw in bl for kw in optical_keywords):
                    file_has_optical = True
                    result['has_optical_bands'] = True

                # Check for vegetation index
                if any(kw in bl for kw in veg_keywords):
                    result['has_vegetation_index'] = True
                    if expr_text:
                        result['vegetation_expression'] = expr_text

                # Check for terrain steepness metric
                if any(kw in bl for kw in terrain_keywords):
                    result['has_terrain_metric'] = True
                    if expr_text:
                        result['terrain_expression'] = expr_text

                # Check for composite band
                if any(kw in bl for kw in composite_keywords):
                    result['has_composite'] = True
                    if expr_text:
                        result['composite_expression'] = expr_text

                # Check for suitability classification
                if any(kw in bl for kw in suit_keywords):
                    result['has_suitability_class'] = True
                    if expr_text:
                        result['suitability_expression'] = expr_text

        if file_has_dem and file_has_optical:
            result['has_multisource_bands'] = True

        # Fallback: detect vegetation index by expression pattern
        if not result['has_vegetation_index']:
            for bname, expr in result.get('virtual_bands', {}).items():
                el = expr.lower().replace(' ', '')
                if ('band_2' in el or 'nir' in el) and \
                   ('band_3' in el or 'red' in el) and \
                   '/' in el and '-' in el:
                    result['has_vegetation_index'] = True
                    result['vegetation_expression'] = expr
                    break

        # Fallback: detect terrain metric by expression referencing DEM/elevation
        if not result['has_terrain_metric']:
            for bname, expr in result.get('virtual_bands', {}).items():
                el = expr.lower().replace(' ', '')
                if any(kw in el for kw in ['elevation', 'dem', 'srtm', 'height']):
                    result['has_terrain_metric'] = True
                    result['terrain_expression'] = expr
                    break

        # Fallback: detect suitability classification by conditional on multiple sources
        if not result['has_suitability_class']:
            for bname, expr in result.get('virtual_bands', {}).items():
                el = expr.lower().replace(' ', '')
                if ('if(' in el or '?' in el) and any(c.isdigit() for c in el):
                    result['has_suitability_class'] = True
                    result['suitability_expression'] = expr
                    break

        # Fallback: detect composite band referencing both veg and terrain
        if not result['has_composite']:
            for bname, expr in result.get('virtual_bands', {}).items():
                el = expr.lower().replace(' ', '')
                refs_veg = any(kw in el for kw in ['ndvi', 'vegetation', 'veg'])
                refs_terr = any(kw in el for kw in ['slope', 'elevation', 'dem',
                                                     'terrain', 'steep'])
                if refs_veg and refs_terr:
                    result['has_composite'] = True
                    result['composite_expression'] = expr
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

with open('/tmp/terrain_vegetation_composite_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/terrain_vegetation_composite_result.json")
PYEOF

echo "=== Export Complete ==="
