#!/bin/bash
echo "=== Exporting resample_resolution_change results ==="

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Extract information via a Python script to reliably parse XML and files
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Retrieve start timestamp
task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    try:
        with open('/tmp/task_start_ts', 'r') as f:
            task_start = int(f.read().strip())
    except:
        pass

result = {
    "task_start_ts": task_start,
    "dim_found": False,
    "dim_created_after_start": False,
    "dim_width": 0,
    "dim_height": 0,
    "dim_bands_count": 0,
    "tif_found": False,
    "tif_created_after_start": False,
    "tif_size_bytes": 0
}

# Directories to search just in case the agent saved it outside of snap_exports
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_data', '/home/ga', '/home/ga/Documents']
expected_dim_name = 'landsat7_resampled.dim'
expected_tif_name = 'landsat7_resampled.tif'

dim_path = None
tif_path = None

# Find files
for d in search_dirs:
    if not dim_path and os.path.exists(os.path.join(d, expected_dim_name)):
        dim_path = os.path.join(d, expected_dim_name)
    if not tif_path and os.path.exists(os.path.join(d, expected_tif_name)):
        tif_path = os.path.join(d, expected_tif_name)

# Analyze DIMAP file
if dim_path:
    result["dim_found"] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime >= task_start:
        result["dim_created_after_start"] = True
        
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        
        # Get dimensions
        ncols = root.find('.//Raster_Dimensions/NCOLS')
        nrows = root.find('.//Raster_Dimensions/NROWS')
        if ncols is not None and ncols.text:
            result["dim_width"] = int(ncols.text)
        if nrows is not None and nrows.text:
            result["dim_height"] = int(nrows.text)
            
        # Get bands count
        bands = root.findall('.//Spectral_Band_Info')
        result["dim_bands_count"] = len(bands)
    except Exception as e:
        print(f"Error parsing DIMAP file: {e}")

# Analyze GeoTIFF file
if tif_path:
    result["tif_found"] = True
    mtime = int(os.path.getmtime(tif_path))
    if mtime >= task_start:
        result["tif_created_after_start"] = True
    result["tif_size_bytes"] = os.path.getsize(tif_path)

# Save results to a temporary JSON
output_path = '/tmp/resample_result.json'
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Results saved to {output_path}")
PYEOF

echo "=== Export complete ==="