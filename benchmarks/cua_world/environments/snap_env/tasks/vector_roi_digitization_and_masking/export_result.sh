#!/bin/bash
echo "=== Exporting vector_roi_digitization_and_masking result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to inspect artifacts and generate JSON report
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Attempt to load PIL for image analysis
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

task_start = 0
ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    with open(ts_file, 'r') as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'polygon_count': 0,
    'vector_container_found': False,
    'masked_band_found': False,
    'masked_band_expression': '',
    'shp_found': False,
    'shp_created_after_start': False,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_zero_percent': 0.0,
    'has_pil': HAS_PIL
}

# 1. Search for BEAM-DIMAP (.dim) and parse XML
dim_path = '/home/ga/snap_projects/field_extraction.dim'
if not os.path.exists(dim_path):
    # Fallback search
    for root_dir, dirs, files in os.walk('/home/ga/snap_projects'):
        for f in files:
            if f.endswith('.dim'):
                dim_path = os.path.join(root_dir, f)
                break

if os.path.exists(dim_path):
    result['dim_found'] = True
    if int(os.path.getmtime(dim_path)) > task_start:
        result['dim_created_after_start'] = True
        
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        
        # Check Vector Data
        for vd in root.iter('Vector_Data_Node'):
            name = vd.attrib.get('name', '')
            if name == 'field_boundaries':
                result['vector_container_found'] = True
                
            # Count polygons regardless of exact container name if it looks like user data
            if name not in ['pins', 'ground_control_points']:
                for geom in vd.iter('geometry'):
                    if geom.text and 'POLYGON' in geom.text:
                        result['polygon_count'] += 1
                        
        # Check Band Maths
        for sbi in root.iter('Spectral_Band_Info'):
            bname_el = sbi.find('BAND_NAME')
            if bname_el is not None and bname_el.text == 'masked_field_data':
                result['masked_band_found'] = True
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                if expr_el is not None and expr_el.text:
                    result['masked_band_expression'] = expr_el.text
                    
    except Exception as e:
        print(f"Error parsing {dim_path}: {e}")

# 2. Check for Shapefile
shp_path = '/home/ga/snap_exports/fields.shp'
if not os.path.exists(shp_path):
    # Fallback search
    for root_dir, dirs, files in os.walk('/home/ga/snap_exports'):
        for f in files:
            if f.endswith('.shp'):
                shp_path = os.path.join(root_dir, f)
                break

if os.path.exists(shp_path):
    result['shp_found'] = True
    if int(os.path.getmtime(shp_path)) > task_start:
        result['shp_created_after_start'] = True

# 3. Check for GeoTIFF and analyze mask
tif_path = '/home/ga/snap_exports/field_extraction.tif'
if not os.path.exists(tif_path):
    # Fallback search
    for root_dir, dirs, files in os.walk('/home/ga/snap_exports'):
        for f in files:
            if f.lower().endswith(('.tif', '.tiff')):
                tif_path = os.path.join(root_dir, f)
                break

if os.path.exists(tif_path):
    result['tif_found'] = True
    if int(os.path.getmtime(tif_path)) > task_start:
        result['tif_created_after_start'] = True
        
    if HAS_PIL:
        try:
            img = Image.open(tif_path)
            # Use the first band for zero check
            hist = img.histogram()
            
            # The histogram is a concatenated list of counts for each band (e.g., 256 * 3 for RGB)
            # hist[0] is the number of 0-value pixels in the first band
            zeros = hist[0]
            total_pixels = img.width * img.height
            
            if total_pixels > 0:
                result['tif_zero_percent'] = (zeros / total_pixels) * 100
        except Exception as e:
            print(f"Error analyzing image {tif_path}: {e}")

# Save JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="