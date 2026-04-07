#!/bin/bash
echo "=== Exporting nonlinear_gamma_radiometric_enhancement result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Execute Python script to safely parse DIMAP XML and check files
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    try:
        task_start = int(open('/tmp/task_start_ts').read().strip())
    except ValueError:
        pass

result = {
    'task_start_time': task_start,
    'dim_exists': False,
    'dim_newly_created': False,
    'dim_band_count': 0,
    'dim_band_names': [],
    'dim_expressions': [],
    'tif_exists': False,
    'tif_newly_created': False,
    'tif_size_bytes': 0,
    'tif_band_count': 0
}

# 1. Analyze DIMAP output
dim_path = '/home/ga/snap_exports/enhanced_coastal.dim'
if os.path.exists(dim_path):
    result['dim_exists'] = True
    if int(os.path.getmtime(dim_path)) > task_start:
        result['dim_newly_created'] = True
    
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        
        # Count bands and extract expressions
        for sbi in root.iter('Spectral_Band_Info'):
            result['dim_band_count'] += 1
            
            bname_node = sbi.find('BAND_NAME')
            if bname_node is not None and bname_node.text:
                result['dim_band_names'].append(bname_node.text.strip())
                
            expr_node = sbi.find('VIRTUAL_BAND_EXPRESSION')
            if expr_node is not None and expr_node.text:
                result['dim_expressions'].append(expr_node.text.strip())
    except Exception as e:
        print(f"Error parsing DIMAP XML: {e}")

# 2. Analyze GeoTIFF output
tif_path = '/home/ga/snap_exports/enhanced_coastal.tif'
if os.path.exists(tif_path):
    result['tif_exists'] = True
    result['tif_size_bytes'] = os.path.getsize(tif_path)
    
    if int(os.path.getmtime(tif_path)) > task_start:
        result['tif_newly_created'] = True
        
    # Attempt to use Pillow to count bands
    try:
        from PIL import Image
        with Image.open(tif_path) as img:
            result['tif_band_count'] = len(img.getbands())
    except Exception as e:
        print(f"Error reading TIFF bands with Pillow: {e}")

# Save result to JSON
output_json = '/tmp/task_result.json'
with open(output_json, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result exported to {output_json}")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="