#!/bin/bash
echo "=== Exporting kmeans_land_cover_classification result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# We will use Python to reliably parse the DIMAP XML and read the GeoTIFF
# This runs safely inside the environment and dumps JSON for the verifier

python3 << 'PYEOF'
import os
import json
import time
import xml.etree.ElementTree as ET

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

# Initialize results dictionary
result = {
    "task_start_time": 0,
    "dimap_found": False,
    "dimap_created_after_start": False,
    "dimap_path": "",
    "class_band_found": False,
    "geotiff_found": False,
    "geotiff_created_after_start": False,
    "geotiff_path": "",
    "geotiff_size_bytes": 0,
    "unique_cluster_count": -1,
    "is_discrete": False,
    "error_log": []
}

# 1. Read task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result["task_start_time"] = int(f.read().strip())
except Exception as e:
    result["error_log"].append(f"Could not read task start time: {e}")

EXPORT_DIR = "/home/ga/snap_exports"
if not os.path.exists(EXPORT_DIR):
    result["error_log"].append(f"Export directory {EXPORT_DIR} not found.")

else:
    # 2. Find and analyze DIMAP file
    dim_files = [f for f in os.listdir(EXPORT_DIR) if f.lower().endswith('.dim')]
    if dim_files:
        dim_path = os.path.join(EXPORT_DIR, dim_files[0])
        result["dimap_found"] = True
        result["dimap_path"] = dim_path
        
        mtime = int(os.path.getmtime(dim_path))
        if mtime > result["task_start_time"]:
            result["dimap_created_after_start"] = True
            
        # Parse XML for class band
        try:
            tree = ET.parse(dim_path)
            root = tree.getroot()
            for sbi in root.iter('Spectral_Band_Info'):
                name_el = sbi.find('BAND_NAME')
                if name_el is not None and name_el.text:
                    if 'class' in name_el.text.lower():
                        result["class_band_found"] = True
                        break
        except Exception as e:
            result["error_log"].append(f"XML parse error: {e}")

    # 3. Find and analyze GeoTIFF file
    tif_files = [f for f in os.listdir(EXPORT_DIR) if f.lower().endswith('.tif') or f.lower().endswith('.tiff')]
    if tif_files:
        tif_path = os.path.join(EXPORT_DIR, tif_files[0])
        result["geotiff_found"] = True
        result["geotiff_path"] = tif_path
        
        mtime = int(os.path.getmtime(tif_path))
        if mtime > result["task_start_time"]:
            result["geotiff_created_after_start"] = True
            
        result["geotiff_size_bytes"] = os.path.getsize(tif_path)
        
        # Analyze values using PIL if available
        if PIL_AVAILABLE:
            try:
                img = Image.open(tif_path)
                # maxcolors limits memory usage; classification map should have < 20 unique values
                colors = img.getcolors(maxcolors=255)
                
                if colors is not None:
                    result["is_discrete"] = True
                    # colors format is [(count1, color1), (count2, color2), ...]
                    # A typical classification map has 5 clusters + 1 possible nodata value
                    result["unique_cluster_count"] = len(colors)
                else:
                    # More than 255 unique colors means it's continuous (e.g. they exported the raw bands, not K-Means)
                    result["is_discrete"] = False
                    result["unique_cluster_count"] = 999
            except Exception as e:
                result["error_log"].append(f"PIL read error: {e}")
        else:
            result["error_log"].append("PIL not available for GeoTIFF value analysis.")

# 4. Save to JSON
with open('/tmp/kmeans_result.json', 'w') as f:
    json.dump(result, f, indent=4)

print("Export logic completed.")
PYEOF

# Ensure the verifier can read the file
chmod 666 /tmp/kmeans_result.json 2>/dev/null || true
echo "Result payload generated:"
cat /tmp/kmeans_result.json

echo "=== Export Complete ==="