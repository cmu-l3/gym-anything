#!/bin/bash
echo "=== Exporting supervised_ml_land_cover result ==="

# 1. Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/supervised_ml_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/supervised_ml_end_screenshot.png 2>/dev/null || true

# 2. Run Python script to parse SNAP processing history and files
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Read task start time
task_start = 0
ts_file = '/tmp/supervised_ml_start_ts'
if os.path.exists(ts_file):
    with open(ts_file, 'r') as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'vector_data_found': False,
    'ml_operator_found': False,
    'ml_operator_name': '',
    'classification_band_found': False,
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# Machine Learning operators in SNAP SMILE
ML_OPERATORS = [
    'Random-Forest-Classifier', 
    'SVM-Classifier', 
    'Maximum-Likelihood-Classifier', 
    'KNN-Classifier', 
    'KDTree-KNN-Classifier', 
    'Minimum-Distance-Classifier',
    'Naive-Bayes-Classifier'
]

# Search for DIMAP (.dim) products
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim') and 'landsat_multispectral' not in f:
                    dim_files.append(os.path.join(root, f))

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        # Check for ML Operator in the processing graph
        for op in root.iter('operator'):
            if op.text and op.text.strip() in ML_OPERATORS:
                result['ml_operator_found'] = True
                result['ml_operator_name'] = op.text.strip()

        # Check for vector data (either in XML or in the .data directory)
        data_dir = dim_file[:-4] + '.data'
        vector_dir = os.path.join(data_dir, 'vector_data')
        
        # Method A: Directory exists and has contents
        if os.path.isdir(vector_dir) and len(os.listdir(vector_dir)) > 0:
            result['vector_data_found'] = True
            
        # Method B: XML Vector nodes
        for vnode in root.iter('Vector_Data_Node'):
            result['vector_data_found'] = True
            break
            
        # Method C: If the ML operator is present, it inherently means vector training data was passed
        if result['ml_operator_found']:
            result['vector_data_found'] = True

        # Check for Classification Band
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.lower()
                if any(kw in bname for kw in ['class', 'label', 'rf_', 'svm_', 'ml_', 'predict']):
                    result['classification_band_found'] = True

    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# Search for GeoTIFF exports
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.lower().endswith(('.tif', '.tiff')) and 'landsat_multispectral' not in f:
                    full_path = os.path.join(root, f)
                    fsize = os.path.getsize(full_path)
                    mtime = int(os.path.getmtime(full_path))
                    
                    if mtime > task_start and fsize > result['tif_file_size']:
                        result['tif_found'] = True
                        result['tif_created_after_start'] = True
                        result['tif_file_size'] = fsize

# Write JSON result
with open('/tmp/supervised_ml_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/supervised_ml_result.json")
PYEOF

echo "=== Export Complete ==="