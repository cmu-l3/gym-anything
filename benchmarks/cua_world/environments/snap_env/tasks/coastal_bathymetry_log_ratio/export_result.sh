#!/bin/bash
echo "=== Exporting coastal_bathymetry_log_ratio result ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract analytical outcomes into JSON
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/sdb_task_start_ts'
if os.path.exists(ts_file):
    try:
        task_start = int(open(ts_file).read().strip())
    except Exception:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'water_mask_band_found': False,
    'water_mask_expression': '',
    'relative_depth_band_found': False,
    'relative_depth_expression': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_size_bytes': 0,
    'xml_dump': ''
}

# Search for BEAM-DIMAP outputs
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith('.dim'):
                dim_files.append(os.path.join(d, f))

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime >= task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True
        
        # Keep XML text around for fallback regex/string parsing
        with open(dim_file, 'r', encoding='utf-8') as f:
            xml_content = f.read()
            result['xml_dump'] += xml_content[:50000]

        tree = ET.parse(dim_file)
        root = tree.getroot()

        # Parse bands inside the XML to inspect Band Math expressions
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            bname = name_el.text.strip() if name_el is not None and name_el.text else ""
            
            expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
            expr_text = expr_el.text.strip() if expr_el is not None and expr_el.text else ""
            
            bname_lower = bname.lower()
            if 'water' in bname_lower or 'mask' in bname_lower:
                result['water_mask_band_found'] = True
                if expr_text:
                    result['water_mask_expression'] = expr_text
            
            if 'depth' in bname_lower or 'bath' in bname_lower or 'relative' in bname_lower or 'log' in bname_lower:
                result['relative_depth_band_found'] = True
                if expr_text:
                    result['relative_depth_expression'] = expr_text
                    
    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# Search for GeoTIFF outputs
tif_dirs = ['/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga']
for d in tif_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.tif', '.tiff')):
                full = os.path.join(d, f)
                if 'snap_data' in full:
                    continue # Skip raw data
                fsize = os.path.getsize(full)
                mtime = int(os.path.getmtime(full))
                
                # Verify it's a product generated during task duration
                if mtime >= task_start and fsize > result['tif_size_bytes']:
                    result['tif_found'] = True
                    result['tif_created_after_start'] = True
                    result['tif_size_bytes'] = fsize

# Export dictionary to json format
with open('/tmp/sdb_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/sdb_task_result.json")
PYEOF

echo "=== Export Complete ==="