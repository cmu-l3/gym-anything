#!/bin/bash
echo "=== Exporting terrain_roughness_assessment result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Extract data using a Python script
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Load task start time
task_start = 0
ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    try:
        task_start = int(open(ts_file).read().strip())
    except:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'dim_path': '',
    'band_names': [],
    'virtual_bands': {},
    'total_band_count': 0,
    'has_roughness_logic': False,
    'roughness_expression': '',
    'has_multiclass_logic': False,
    'classification_expression': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0,
    'tif_path': ''
}

# 1. Search for .dim files
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            if 'snap_data' in root:
                continue
            for f in files:
                if f.endswith('.dim'):
                    dim_files.append(os.path.join(root, f))

# Parse DIMAP files
for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True
        result['dim_path'] = dim_file

        tree = ET.parse(dim_file)
        root = tree.getroot()

        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['band_names'].append(bname)
                result['total_band_count'] += 1

                # Check virtual expressions
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                if expr_el is not None and expr_el.text:
                    expr = expr_el.text.strip()
                    result['virtual_bands'][bname] = expr
                    
                    expr_lower = expr.lower()
                    
                    # Detect Roughness Derivation: Contains subtraction '-'
                    if '-' in expr_lower:
                        result['has_roughness_logic'] = True
                        result['roughness_expression'] = expr
                        
                    # Detect Multi-Class Classification: nested ternaries or multiple IFs
                    q_count = expr_lower.count('?')
                    if_count = expr_lower.count('if ') + expr_lower.count('if(')
                    if q_count >= 2 or if_count >= 2:
                        result['has_multiclass_logic'] = True
                        result['classification_expression'] = expr
                        
    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# 2. Search for exported GeoTIFF files
tif_dirs = ['/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga', '/tmp']
for d in tif_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            if 'snap_data' in root:
                continue
            for f in files:
                if f.lower().endswith(('.tif', '.tiff')):
                    full = os.path.join(root, f)
                    fsize = os.path.getsize(full)
                    mtime = int(os.path.getmtime(full))
                    
                    if mtime > task_start and fsize > result['tif_file_size']:
                        result['tif_found'] = True
                        result['tif_created_after_start'] = True
                        result['tif_file_size'] = fsize
                        result['tif_path'] = full

# Save result JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON generated successfully.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="