#!/bin/bash
echo "=== Exporting pca_spectral_feature_extraction result ==="

source /workspace/utils/task_utils.sh 2>/dev/null || true

if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_end.png
else
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true
fi

python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/pca_task_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'pc_band_count': 0,
    'spectral_anomaly_exists': False,
    'anomaly_expression': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0,
    'tif_band_count': 0
}

# 1. Search for the DIMAP file
dim_file = '/home/ga/snap_exports/landsat_pca.dim'
# Fallbacks if agent saved it elsewhere
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
if not os.path.exists(dim_file):
    for d in search_dirs:
        for root, dirs, files in os.walk(d):
            if 'snap_data' in root:
                continue
            for f in files:
                if f.endswith('.dim') and ('pca' in f.lower() or 'landsat' in f.lower()):
                    dim_file = os.path.join(root, f)
                    break

if os.path.exists(dim_file):
    result['dim_found'] = True
    if int(os.path.getmtime(dim_file)) > task_start:
        result['dim_created_after_start'] = True

    try:
        tree = ET.parse(dim_file)
        root = tree.getroot()
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip().lower()

                # Check for PCA bands (usually "PC1", "PC2", "component_1", etc.)
                if 'pc' in bname or 'component' in bname or 'pca' in bname:
                    result['pc_band_count'] += 1

                # Check for spectral_anomaly band
                if bname == 'spectral_anomaly':
                    result['spectral_anomaly_exists'] = True
                    expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                    if expr_el is not None and expr_el.text:
                        result['anomaly_expression'] = expr_el.text.strip()
    except Exception as e:
        print(f"Error parsing dim file {dim_file}: {e}")

# 2. Search for the GeoTIFF file
tif_file = '/home/ga/snap_exports/landsat_pca.tif'
if not os.path.exists(tif_file):
    for d in search_dirs:
        for root, dirs, files in os.walk(d):
            if 'snap_data' in root:
                continue
            for f in files:
                if f.endswith('.tif') and ('pca' in f.lower() or 'landsat' in f.lower()):
                    tif_file = os.path.join(root, f)
                    break

if os.path.exists(tif_file):
    result['tif_found'] = True
    result['tif_file_size'] = os.path.getsize(tif_file)
    if int(os.path.getmtime(tif_file)) > task_start:
        result['tif_created_after_start'] = True

    try:
        from PIL import Image
        img = Image.open(tif_file)
        result['tif_band_count'] = getattr(img, 'n_frames', 1)
    except Exception as e:
        print(f"Error parsing tif file {tif_file}: {e}")

with open('/tmp/pca_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/pca_task_result.json")
PYEOF

echo "=== Export Complete ==="