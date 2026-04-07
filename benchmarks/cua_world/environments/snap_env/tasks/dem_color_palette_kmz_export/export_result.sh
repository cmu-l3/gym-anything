#!/bin/bash
echo "=== Exporting dem_color_palette_kmz_export result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Parse results using Python
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET
import zipfile

task_start = 0
ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    with open(ts_file, 'r') as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

result = {
    'task_start': task_start,
    
    'dim_exists': False,
    'dim_created_after_start': False,
    'dim_size_bytes': 0,
    'has_color_palette': False,
    'is_non_grayscale': False,
    
    'kmz_exists': False,
    'kmz_created_after_start': False,
    'kmz_size_bytes': 0,
    'kmz_is_valid_zip': False,
    'kmz_has_kml': False,
    'kmz_has_image': False
}

dim_path = '/home/ga/snap_exports/dem_colored.dim'
kmz_path = '/home/ga/snap_exports/dem_terrain.kmz'

# Optional fallback paths if agent saved somewhere else
if not os.path.exists(dim_path):
    alt_dims = [f for f in os.listdir('/home/ga/snap_exports') if f.endswith('.dim')]
    if alt_dims: dim_path = os.path.join('/home/ga/snap_exports', alt_dims[0])

if not os.path.exists(kmz_path):
    alt_kmzs = [f for f in os.listdir('/home/ga/snap_exports') if f.endswith('.kmz')]
    if alt_kmzs: kmz_path = os.path.join('/home/ga/snap_exports', alt_kmzs[0])

# Check DIMAP
if os.path.exists(dim_path):
    result['dim_exists'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime > task_start:
        result['dim_created_after_start'] = True
    result['dim_size_bytes'] = os.path.getsize(dim_path)
    
    # Parse DIMAP XML to verify color palette
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        
        has_palette = False
        non_grayscale = False
        
        for pt in root.iter('Color_Palette_Point'):
            has_palette = True
            color_el = pt.find('color')
            if color_el is not None and color_el.text:
                # Colors usually format like "255,128,0"
                parts = color_el.text.strip().split(',')
                if len(parts) >= 3:
                    r, g, b = parts[0], parts[1], parts[2]
                    # If R!=G or G!=B, it's not a pure grayscale color
                    if r != g or g != b:
                        non_grayscale = True
                        
        result['has_color_palette'] = has_palette
        result['is_non_grayscale'] = non_grayscale
    except Exception as e:
        print(f"Error parsing DIMAP XML: {e}")

# Check KMZ
if os.path.exists(kmz_path):
    result['kmz_exists'] = True
    mtime = int(os.path.getmtime(kmz_path))
    if mtime > task_start:
        result['kmz_created_after_start'] = True
    result['kmz_size_bytes'] = os.path.getsize(kmz_path)
    
    # Verify KMZ ZIP structure
    if zipfile.is_zipfile(kmz_path):
        result['kmz_is_valid_zip'] = True
        try:
            with zipfile.ZipFile(kmz_path, 'r') as z:
                files = z.namelist()
                for f in files:
                    fl = f.lower()
                    if fl.endswith('.kml'):
                        result['kmz_has_kml'] = True
                    if fl.endswith('.png') or fl.endswith('.jpg') or fl.endswith('.jpeg'):
                        result['kmz_has_image'] = True
        except Exception as e:
            print(f"Error reading KMZ zip: {e}")

with open('/tmp/kmz_export_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export result generated at /tmp/kmz_export_result.json")
PYEOF

echo "=== Export Complete ==="