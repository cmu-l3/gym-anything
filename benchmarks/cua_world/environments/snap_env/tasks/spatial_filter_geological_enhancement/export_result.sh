#!/bin/bash
echo "=== Exporting Spatial Filter Geological Enhancement result ==="

# Capture final state
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Execute embedded Python script to safely parse DIMAP XML and locate outputs
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

result = {
    'task_start': 0,
    'dim_found': False,
    'dim_created_after_start': False,
    'dim_file_path': '',
    'total_band_count': 0,
    'has_edge_filter': False,
    'has_smooth_filter': False,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0,
    'tif_file_path': ''
}

# 1. Get task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start'] = int(f.read().strip())
except Exception:
    pass

# 2. Search for the saved DIMAP (.dim) file
search_dirs = ['/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim') and 'snap_data' not in root:
                    dim_files.append(os.path.join(root, f))

# Keywords for filter types
edge_keywords = ['sobel', 'roberts', 'prewitt', 'laplace', 'laplacian', 'edge', 
                 'high_pass', 'highpass', 'compass', 'gradient', 'kirsch', 
                 'frei', 'sharpen', 'emboss', 'north', 'south', 'east', 'west']
smooth_keywords = ['mean', 'gaussian', 'gauss', 'low_pass', 'lowpass', 
                   'smooth', 'average', 'median', 'blur']

# Parse the most recently modified valid DIMAP file
latest_dim = None
latest_mtime = 0

for dim_file in dim_files:
    mtime = int(os.path.getmtime(dim_file))
    if mtime > latest_mtime:
        latest_mtime = mtime
        latest_dim = dim_file

if latest_dim:
    result['dim_found'] = True
    result['dim_file_path'] = latest_dim
    if latest_mtime >= result['task_start']:
        result['dim_created_after_start'] = True
        
    try:
        tree = ET.parse(latest_dim)
        root = tree.getroot()
        
        # Check bands
        for sbi in root.iter('Spectral_Band_Info'):
            result['total_band_count'] += 1
            
            bname = sbi.findtext('BAND_NAME', '').lower()
            desc = sbi.findtext('DESCRIPTION', '').lower()
            text_to_check = bname + " " + desc
            
            if any(kw in text_to_check for kw in edge_keywords):
                result['has_edge_filter'] = True
            if any(kw in text_to_check for kw in smooth_keywords):
                result['has_smooth_filter'] = True
    except Exception as e:
        print(f"Error parsing DIMAP file {latest_dim}: {e}")

# 3. Search for exported GeoTIFF file
tif_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
latest_tif = None
latest_tif_mtime = 0

for d in tif_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.lower().endswith(('.tif', '.tiff')) and 'snap_data' not in root:
                    full_path = os.path.join(root, f)
                    mtime = int(os.path.getmtime(full_path))
                    if mtime > latest_tif_mtime:
                        latest_tif_mtime = mtime
                        latest_tif = full_path

if latest_tif:
    result['tif_found'] = True
    result['tif_file_path'] = latest_tif
    result['tif_file_size'] = os.path.getsize(latest_tif)
    if latest_tif_mtime >= result['task_start']:
        result['tif_created_after_start'] = True

# Write result securely
with open('/tmp/spatial_filter_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Analysis results saved to /tmp/spatial_filter_result.json")
PYEOF

echo "=== Export Complete ==="