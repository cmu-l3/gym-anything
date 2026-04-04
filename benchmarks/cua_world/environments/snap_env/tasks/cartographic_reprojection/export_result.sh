#!/bin/bash
echo "=== Exporting cartographic_reprojection result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/cartographic_reprojection_end_screenshot.png

python3 << 'PYEOF'
import os, json, xml.etree.ElementTree as ET, re

task_start = 0
ts_file = '/tmp/cartographic_reprojection_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'crs_wkt': '',
    'crs_changed': False,
    'original_crs_wkt': '',
    'raster_width': 0,
    'raster_height': 0,
    'original_width': 0,
    'original_height': 0,
    'dimensions_changed': False,
    'has_bands': False,
    'band_count': 0,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# Try to load original properties
orig_file = '/tmp/cartographic_reprojection_original.json'
if os.path.exists(orig_file):
    try:
        orig = json.load(open(orig_file))
        result['original_crs_wkt'] = orig.get('crs', '')
        sz = orig.get('size', [])
        if len(sz) >= 2:
            result['original_width'] = sz[0]
            result['original_height'] = sz[1]
    except Exception:
        pass

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

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        # Extract CRS
        for crs_el in root.iter('Coordinate_Reference_System'):
            wkt_el = crs_el.find('.//WKT')
            if wkt_el is not None and wkt_el.text:
                result['crs_wkt'] = wkt_el.text.strip()
        # Also check for HORIZONTAL_CS_NAME
        for cs_el in root.iter('HORIZONTAL_CS_NAME'):
            if cs_el.text:
                result['crs_wkt'] = result['crs_wkt'] or cs_el.text.strip()

        # Extract raster dimensions
        for rd in root.iter('Raster_Dimensions'):
            ncols = rd.find('NCOLS')
            nrows = rd.find('NROWS')
            if ncols is not None and ncols.text:
                result['raster_width'] = int(ncols.text)
            if nrows is not None and nrows.text:
                result['raster_height'] = int(nrows.text)

        # Count bands
        band_count = 0
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None:
                band_count += 1
        result['band_count'] = band_count
        result['has_bands'] = band_count > 0

    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# Detect CRS change
if result['crs_wkt'] and result['original_crs_wkt']:
    # Simple check: if the WKT strings differ significantly
    if result['crs_wkt'][:50] != result['original_crs_wkt'][:50]:
        result['crs_changed'] = True
elif result['crs_wkt']:
    # Check for projected CRS keywords (UTM, Mercator, etc.)
    crs_lower = result['crs_wkt'].lower()
    if any(kw in crs_lower for kw in ['utm', 'mercator', 'transverse',
                                       'lambert', 'albers', 'mollweide',
                                       'projected', 'projcs']):
        result['crs_changed'] = True

# Detect dimension change (subset)
if (result['raster_width'] > 0 and result['original_width'] > 0 and
    (result['raster_width'] != result['original_width'] or
     result['raster_height'] != result['original_height'])):
    result['dimensions_changed'] = True

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

with open('/tmp/cartographic_reprojection_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/cartographic_reprojection_result.json")
PYEOF

echo "=== Export Complete ==="
