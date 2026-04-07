#!/bin/bash
echo "=== Exporting subset_reproject_to_wgs84 result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Run GDAL info on the expected GeoTIFF if it exists
TIF_FILE="/home/ga/snap_exports/landsat_subset_wgs84.tif"
if [ -f "$TIF_FILE" ] && command -v gdalinfo &> /dev/null; then
    gdalinfo -json "$TIF_FILE" > /tmp/gdal_info.json 2>/dev/null || echo "{}" > /tmp/gdal_info.json
else
    echo "{}" > /tmp/gdal_info.json
fi

# 3. Python script to aggregate data from DIMAP XML and GDAL JSON
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    with open('/tmp/task_start_ts') as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'dim_exists': False,
    'dim_created_after_start': False,
    'dim_width': 0,
    'dim_height': 0,
    'dim_bands': 0,
    'dim_crs': '',
    'dim_datum': '',
    'tif_exists': False,
    'tif_created_after_start': False,
    'tif_size_bytes': 0,
    'gdal_crs_wkt': '',
    'gdal_width': 0,
    'gdal_height': 0,
    'gdal_bands': 0,
    'gdal_is_geographic_bounds': False
}

# --- Analyze DIMAP (.dim) XML ---
dim_file = '/home/ga/snap_projects/landsat_subset_wgs84.dim'
if os.path.exists(dim_file):
    result['dim_exists'] = True
    if os.path.getmtime(dim_file) > task_start:
        result['dim_created_after_start'] = True
        
    try:
        tree = ET.parse(dim_file)
        root = tree.getroot()
        
        ncols = root.find('.//Raster_Dimensions/NCOLS')
        if ncols is not None: result['dim_width'] = int(ncols.text)
        
        nrows = root.find('.//Raster_Dimensions/NROWS')
        if nrows is not None: result['dim_height'] = int(nrows.text)
        
        bands = root.findall('.//Spectral_Band_Info')
        result['dim_bands'] = len(bands)
        
        proj = root.find('.//Coordinate_Reference_System/Projection_Name')
        if proj is not None: result['dim_crs'] = proj.text
        
        datum = root.find('.//Coordinate_Reference_System/Geodetic_Datum')
        if datum is not None: result['dim_datum'] = datum.text
    except Exception as e:
        result['dim_error'] = str(e)

# --- Analyze GeoTIFF (.tif) and GDAL JSON ---
tif_file = '/home/ga/snap_exports/landsat_subset_wgs84.tif'
if os.path.exists(tif_file):
    result['tif_exists'] = True
    result['tif_size_bytes'] = os.path.getsize(tif_file)
    if os.path.getmtime(tif_file) > task_start:
        result['tif_created_after_start'] = True

try:
    with open('/tmp/gdal_info.json') as f:
        gdal_data = json.load(f)
        
    if gdal_data:
        size = gdal_data.get('size', [0, 0])
        result['gdal_width'] = size[0]
        result['gdal_height'] = size[1]
        
        bands = gdal_data.get('bands', [])
        result['gdal_bands'] = len(bands)
        
        coord_sys = gdal_data.get('coordinateSystem', {})
        result['gdal_crs_wkt'] = coord_sys.get('wkt', '')
        
        # Check geographic bounds (-180 to 180, -90 to 90)
        corners = gdal_data.get('cornerCoordinates', {})
        valid_corners = 0
        for key, coords in corners.items():
            if isinstance(coords, list) and len(coords) >= 2:
                lon, lat = coords[0], coords[1]
                if -180.5 <= lon <= 180.5 and -90.5 <= lat <= 90.5:
                    valid_corners += 1
        
        if valid_corners >= 4:
            result['gdal_is_geographic_bounds'] = True
            
except Exception as e:
    result['gdal_error'] = str(e)

# Write to final result path
with open('/tmp/subset_reproject_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export JSON complete.")
PYEOF

echo "=== Export Complete ==="