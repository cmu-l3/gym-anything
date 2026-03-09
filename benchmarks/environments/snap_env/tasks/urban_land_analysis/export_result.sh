#!/bin/bash
echo "=== Exporting urban_land_analysis result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/urban_land_analysis_end_screenshot.png

python3 << 'PYEOF'
import os, json, xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/urban_land_analysis_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'band_names': [],
    'virtual_bands': {},
    'total_band_count': 0,
    'has_ndbi': False,
    'has_ndvi': False,
    'has_urban_diff': False,
    'has_zoning': False,
    'ndbi_expression': '',
    'ndvi_expression': '',
    'urban_diff_expression': '',
    'zoning_expression': '',
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

# Keywords for urban analysis bands
ndbi_keywords = ['ndbi', 'built', 'buildup', 'built_up', 'impervious', 'urban_index']
ndvi_keywords = ['ndvi', 'vegetation', 'veg_index', 'greenness']
diff_keywords = ['diff', 'urban_veg', 'contrast', 'bu_vi', 'ndbi_ndvi',
                 'built_veg', 'differential', 'delta']
zone_keywords = ['zone', 'zoning', 'class', 'urban_zone', 'land_use',
                 'landuse', 'categ', 'type', 'cover']

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

                if any(kw in bl for kw in ndbi_keywords):
                    result['has_ndbi'] = True
                    if expr_text:
                        result['ndbi_expression'] = expr_text

                if any(kw in bl for kw in ndvi_keywords):
                    result['has_ndvi'] = True
                    if expr_text:
                        result['ndvi_expression'] = expr_text

                if any(kw in bl for kw in diff_keywords):
                    result['has_urban_diff'] = True
                    if expr_text:
                        result['urban_diff_expression'] = expr_text

                if any(kw in bl for kw in zone_keywords):
                    result['has_zoning'] = True
                    if expr_text:
                        result['zoning_expression'] = expr_text

        # Fallback detection via expression analysis
        for bname, expr in result.get('virtual_bands', {}).items():
            el = expr.lower().replace(' ', '')

            # Detect NDBI: (SWIR-NIR)/(SWIR+NIR) = (band_1-band_2)/(band_1+band_2)
            if not result['has_ndbi']:
                if ('band_1' in el or 'swir' in el) and ('band_2' in el or 'nir' in el):
                    if '/' in el and '-' in el and '+' in el:
                        # Make sure it's not NDVI (band_2-band_3)
                        if 'band_3' not in el and 'red' not in el:
                            result['has_ndbi'] = True
                            result['ndbi_expression'] = expr

            # Detect NDVI: (NIR-Red)/(NIR+Red) = (band_2-band_3)/(band_2+band_3)
            if not result['has_ndvi']:
                if ('band_2' in el or 'nir' in el) and ('band_3' in el or 'red' in el):
                    if '/' in el and '-' in el and '+' in el:
                        result['has_ndvi'] = True
                        result['ndvi_expression'] = expr

            # Detect urban-vegetation difference: NDBI - NDVI or similar subtraction
            if not result['has_urban_diff']:
                if ('ndbi' in el or 'built' in el) and ('ndvi' in el or 'veg' in el):
                    if '-' in el:
                        result['has_urban_diff'] = True
                        result['urban_diff_expression'] = expr

            # Detect zoning via conditional expressions
            if not result['has_zoning']:
                if 'if(' in el or 'if (' in el or '?' in el:
                    if any(c.isdigit() for c in el):
                        result['has_zoning'] = True
                        result['zoning_expression'] = expr

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

with open('/tmp/urban_land_analysis_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/urban_land_analysis_result.json")
PYEOF

echo "=== Export Complete ==="
