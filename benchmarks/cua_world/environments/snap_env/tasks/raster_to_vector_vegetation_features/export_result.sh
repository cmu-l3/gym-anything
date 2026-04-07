#!/bin/bash
echo "=== Exporting Raster to Vector Conversion Result ==="

# 1. Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python script to inspect output files and calculate properties
python3 << 'PYEOF'
import os
import json
import struct
import xml.etree.ElementTree as ET

result = {
    'task_start': 0,
    'dim_exists': False,
    'dim_created_after_start': False,
    'ndvi_band_exists': False,
    'ndvi_expression': '',
    'shp_exists': False,
    'shx_exists': False,
    'dbf_exists': False,
    'shp_size': 0,
    'shp_magic_valid': False
}

# Read task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start'] = int(f.read().strip())
except Exception as e:
    print(f"Warning: Could not read start time: {e}")

# Check DIMAP project
dim_path = '/home/ga/snap_projects/vegetation_analysis.dim'
if os.path.exists(dim_path):
    result['dim_exists'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime >= result['task_start']:
        result['dim_created_after_start'] = True
    
    # Parse XML to find NDVI
    try:
        tree = ET.parse(dim_path)
        for sbi in tree.iter('Spectral_Band_Info'):
            bname = sbi.find('BAND_NAME')
            if bname is not None and bname.text and bname.text.lower() == 'ndvi':
                result['ndvi_band_exists'] = True
                expr = sbi.find('VIRTUAL_BAND_EXPRESSION')
                if expr is not None and expr.text:
                    result['ndvi_expression'] = expr.text.lower()
    except Exception as e:
        print(f"Warning: Failed to parse DIMAP XML: {e}")

# Check Shapefile components
shp_path = '/home/ga/snap_exports/dense_vegetation.shp'
shx_path = '/home/ga/snap_exports/dense_vegetation.shx'
dbf_path = '/home/ga/snap_exports/dense_vegetation.dbf'

if os.path.exists(shp_path):
    result['shp_exists'] = True
    result['shp_size'] = os.path.getsize(shp_path)
    
    # Read magic bytes to ensure it's an actual ESRI Shapefile (0x0000270A -> 9994)
    try:
        with open(shp_path, 'rb') as f:
            magic = f.read(4)
            if len(magic) == 4:
                magic_int = struct.unpack('>I', magic)[0]
                if magic_int == 9994:
                    result['shp_magic_valid'] = True
    except Exception as e:
        print(f"Warning: Failed to read Shapefile magic bytes: {e}")

if os.path.exists(shx_path):
    result['shx_exists'] = True
if os.path.exists(dbf_path):
    result['dbf_exists'] = True

# Write output JSON
with open('/tmp/raster_to_vector_result.json', 'w') as f:
    json.dump(result, f, indent=4)
PYEOF

echo "Result JSON written to /tmp/raster_to_vector_result.json"
cat /tmp/raster_to_vector_result.json

echo "=== Export complete ==="