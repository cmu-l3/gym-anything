#!/bin/bash
echo "=== Exporting tpi_landform_classification result ==="

# Take a screenshot of the final state
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Execute Python script inside the container to safely analyze SNAP outputs
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET
import numpy as np
import cv2

task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    with open('/tmp/task_start_ts', 'r') as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'total_band_count': 0,
    'tif_found': False,
    'tif_created_after_start': False,
    'unique_classes_count': 0,
    'max_class_percentage': 0.0,
    'tif_file_size': 0
}

export_dir = '/home/ga/snap_exports'

# 1. Look for the BEAM-DIMAP file
dim_path = None
if os.path.exists(export_dir):
    for root, dirs, files in os.walk(export_dir):
        for f in files:
            if f.endswith('.dim'):
                dim_path = os.path.join(root, f)
                break

if dim_path:
    result['dim_found'] = True
    if int(os.path.getmtime(dim_path)) > task_start:
        result['dim_created_after_start'] = True
        
    try:
        tree = ET.parse(dim_path)
        root_xml = tree.getroot()
        bands = [sbi.find('BAND_NAME') for sbi in root_xml.iter('Spectral_Band_Info')]
        result['total_band_count'] = len(bands)
    except Exception as e:
        print(f"Error parsing DIMAP XML: {e}")

# 2. Look for the exported GeoTIFF classification map
tif_path = None
if os.path.exists(export_dir):
    for root, dirs, files in os.walk(export_dir):
        for f in files:
            if f.endswith('.tif') or f.endswith('.tiff'):
                tif_path = os.path.join(root, f)
                break

if tif_path:
    result['tif_found'] = True
    result['tif_file_size'] = os.path.getsize(tif_path)
    
    if int(os.path.getmtime(tif_path)) > task_start:
        result['tif_created_after_start'] = True

    # Read the TIFF safely using OpenCV (handles basic single-band GeoTIFFs well)
    try:
        img = cv2.imread(tif_path, cv2.IMREAD_UNCHANGED)
        if img is not None:
            # Flatten to 1D and remove NaNs / zero-padding masks
            valid_pixels = img.flatten()
            valid_pixels = valid_pixels[~np.isnan(valid_pixels)]
            
            if len(valid_pixels) > 0:
                unique_vals, counts = np.unique(valid_pixels, return_counts=True)
                
                # Exclude obvious empty filler values (0 or -9999 if they dominate 99% unconditionally, though 0 might be slope)
                # But to strictly count valid classes, we just measure distinct numeric occurrences
                result['unique_classes_count'] = len(unique_vals)
                result['max_class_percentage'] = float(np.max(counts) / len(valid_pixels)) * 100
    except Exception as e:
        print(f"Error reading GeoTIFF image: {e}")

# Write results
with open('/tmp/tpi_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result analysis saved to /tmp/tpi_result.json")
PYEOF

echo "=== Export Complete ==="