#!/bin/bash
echo "=== Exporting masked_water_mass_clustering result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Extract data using Python parser
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

result = {
    'task_start': 0,
    'dim_found': False,
    'dim_created_after_start': False,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_size_bytes': 0,
    'has_class_indices': False,
    'kmeans_run': False,
    'kmeans_source_bands': "",
    'has_nan_logic': False,
    'virtual_bands': {}
}

# Get task start time
ts_file = '/tmp/masked_water_mass_clustering_start_ts'
if os.path.exists(ts_file):
    try:
        result['task_start'] = int(open(ts_file).read().strip())
    except:
        pass

# 1. Search for output DIMAP files
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim'):
                    full_path = os.path.join(root, f)
                    if 'snap_data' not in full_path:
                        dim_files.append(full_path)

# 2. Parse the DIMAP XML metadata
for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > result['task_start']:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        # Check bands
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                if 'class_indices' in bname.lower():
                    result['has_class_indices'] = True
                
                # Check for virtual band expressions
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                if expr_el is not None and expr_el.text:
                    expr = expr_el.text.strip()
                    result['virtual_bands'][bname] = expr
                    
                    # Check for explicit NaN injection and conditional logic
                    expr_lower = expr.lower().replace(' ', '')
                    has_nan = 'nan' in expr_lower
                    has_cond = 'if' in expr_lower or '?' in expr_lower
                    if has_nan and has_cond:
                        result['has_nan_logic'] = True

        # Check processing graph for K-Means operation
        for node in root.findall(".//node"):
            node_id = node.get("id", "")
            if "KMeansClusterAnalysis" in node_id:
                result['kmeans_run'] = True
                sb_el = node.find(".//parameters/sourceBands")
                if sb_el is not None and sb_el.text:
                    result['kmeans_source_bands'] = sb_el.text
                break
                
    except Exception as e:
        print(f"Error parsing DIMAP {dim_file}: {e}")

# 3. Search for GeoTIFF exports
for d in search_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.tif', '.tiff')):
                full_path = os.path.join(d, f)
                if 'snap_data' not in full_path:
                    try:
                        fsize = os.path.getsize(full_path)
                        mtime = int(os.path.getmtime(full_path))
                        if mtime > result['task_start'] and fsize > result['tif_size_bytes']:
                            result['tif_found'] = True
                            result['tif_created_after_start'] = True
                            result['tif_size_bytes'] = fsize
                    except:
                        pass

# 4. Save results for verifier
with open('/tmp/masked_water_mass_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export completed successfully.")
PYEOF

echo "=== Export Complete ==="