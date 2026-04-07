#!/bin/bash
echo "=== Exporting topographic_profile_extraction result ==="

source /workspace/utils/task_utils.sh

# Take final screenshot of the agent's work
take_screenshot /tmp/task_end_screenshot.png

# Parse task artifacts
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Read task start timestamp
task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    try:
        task_start = int(open('/tmp/task_start_ts').read().strip())
    except Exception:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'has_vector_data': False,
    'txt_found': False,
    'txt_created_after_start': False,
    'txt_row_count': 0,
    'elevation_min': 0.0,
    'elevation_max': 0.0,
    'elevation_variance': 0.0
}

# 1. Check BEAM-DIMAP Product
dim_path = '/home/ga/snap_exports/dem_transect.dim'
if os.path.exists(dim_path):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime > task_start:
        result['dim_created_after_start'] = True
    
    # Check for Vector Node in XML
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        vector_nodes = list(root.iter('VectorDataNode'))
        if len(vector_nodes) > 0:
            result['has_vector_data'] = True
    except Exception as e:
        print(f"Error parsing XML: {e}")
        
    # Check for vector_data in the .data directory as fallback
    data_dir = dim_path.replace('.dim', '.data')
    vec_dir = os.path.join(data_dir, 'vector_data')
    if os.path.exists(vec_dir) and len(os.listdir(vec_dir)) > 0:
        result['has_vector_data'] = True

# 2. Check Profile Text File
txt_path = '/home/ga/snap_exports/pipeline_profile.txt'
if os.path.exists(txt_path):
    result['txt_found'] = True
    mtime = int(os.path.getmtime(txt_path))
    if mtime > task_start:
        result['txt_created_after_start'] = True
        
    # Parse table to find elevation points and variance
    try:
        with open(txt_path, 'r') as f:
            lines = f.readlines()
        
        data_rows = []
        for line in lines:
            line = line.strip()
            if not line:
                continue
                
            # Chart exports are usually tab-separated or comma-separated
            parts = line.split('\t')
            if len(parts) < 2:
                parts = line.split(',')
                
            # The band value (elevation) is typically the last numeric column
            try:
                val = float(parts[-1].strip())
                data_rows.append(val)
            except ValueError:
                # Skip header rows
                pass
                
        result['txt_row_count'] = len(data_rows)
        if len(data_rows) > 0:
            result['elevation_min'] = min(data_rows)
            result['elevation_max'] = max(data_rows)
            result['elevation_variance'] = max(data_rows) - min(data_rows)
            
    except Exception as e:
        print(f"Error parsing profile txt: {e}")

# Write results
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export JSON created at /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="