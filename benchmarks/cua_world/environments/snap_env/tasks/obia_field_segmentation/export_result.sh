#!/bin/bash
echo "=== Exporting obia_field_segmentation results ==="

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Use Python to analyze the expected output files
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Attempt to load array processing libraries
try:
    import numpy as np
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None  # Suppress DecompressionBombWarning for large TIFFs
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

result = {
    'task_start_ts': 0,
    'dimap_found': False,
    'dimap_created_during_task': False,
    'has_grm_operator': False,
    'has_label_band': False,
    'band_names': [],
    'geotiff_found': False,
    'geotiff_created_during_task': False,
    'geotiff_size_bytes': 0,
    'unique_objects_count': 0,
    'has_numpy': HAS_NUMPY
}

# Read start timestamp
ts_file = '/tmp/obia_task_start_ts'
if os.path.exists(ts_file):
    try:
        result['task_start_ts'] = int(open(ts_file).read().strip())
    except:
        pass

# Paths to check
dimap_path = '/home/ga/snap_exports/field_segments.dim'
geotiff_path = '/home/ga/snap_exports/field_segments.tif'

# 1. Analyze BEAM-DIMAP File
if os.path.exists(dimap_path):
    result['dimap_found'] = True
    mtime = int(os.path.getmtime(dimap_path))
    if mtime > result['task_start_ts']:
        result['dimap_created_during_task'] = True
    
    # Parse XML content
    try:
        with open(dimap_path, 'r', encoding='utf-8') as f:
            xml_content = f.read()
            # The exact operator name for Generic Region Merging in SNAP
            if 'GenericRegionMerging' in xml_content or 'Generic Region Merging' in xml_content:
                result['has_grm_operator'] = True

        tree = ET.parse(dimap_path)
        root = tree.getroot()
        
        # Extract band names and check for segmentation label band
        for sbi in root.iter('Spectral_Band_Info'):
            bname_node = sbi.find('BAND_NAME')
            if bname_node is not None and bname_node.text:
                bname = bname_node.text.strip()
                result['band_names'].append(bname)
                bname_lower = bname.lower()
                
                # Check for characteristic GRM output names
                if any(kw in bname_lower for kw in ['label', 'segment', 'grm', 'merge']):
                    result['has_label_band'] = True
    except Exception as e:
        print(f"Error parsing DIMAP XML: {e}")

# 2. Analyze GeoTIFF File
if os.path.exists(geotiff_path):
    result['geotiff_found'] = True
    mtime = int(os.path.getmtime(geotiff_path))
    if mtime > result['task_start_ts']:
        result['geotiff_created_during_task'] = True
        
    result['geotiff_size_bytes'] = os.path.getsize(geotiff_path)
    
    if HAS_NUMPY and result['geotiff_size_bytes'] > 1024:
        try:
            img = Image.open(geotiff_path)
            arr = np.array(img)
            
            # Count unique values to prove segmentation occurred
            # If the agent just exported RGB, the unique values will be very high (thousands).
            # If they exported a label map, it will be the number of segments.
            # Both indicate complex data, whereas faking a solid color box would be 1 unique value.
            if len(arr.shape) == 3:
                # 3D array (e.g., multi-band exported TIFF)
                # Reshape to list of pixels and count unique pixel signatures
                reshaped = arr.reshape(-1, arr.shape[-1])
                unique_vals = len(np.unique(reshaped, axis=0))
            else:
                # 2D array (e.g., single label band exported)
                unique_vals = len(np.unique(arr))
                
            result['unique_objects_count'] = int(unique_vals)
        except Exception as e:
            print(f"Error analyzing GeoTIFF array: {e}")

# Write results
with open('/tmp/obia_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete. Result metrics written.")
PYEOF

# Ensure file permissions are readable
chmod 666 /tmp/obia_task_result.json 2>/dev/null || true

echo "=== Export process finished ==="