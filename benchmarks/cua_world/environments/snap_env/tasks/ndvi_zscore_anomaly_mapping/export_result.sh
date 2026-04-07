#!/bin/bash
echo "=== Exporting ndvi_zscore_anomaly_mapping result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Ensure numpy and pillow are available for math verification
if ! python3 -c "import numpy" &> /dev/null; then
    echo "Installing numpy..."
    apt-get update -qq && apt-get install -y python3-numpy 2>/dev/null || pip3 install numpy 2>/dev/null
fi
if ! python3 -c "import PIL" &> /dev/null; then
    apt-get install -y python3-pil 2>/dev/null || pip3 install pillow 2>/dev/null
fi

# Run embedded Python script to extract metadata and perform math proof on outputs
python3 << 'EOF'
import os
import json
import xml.etree.ElementTree as ET
try:
    import numpy as np
except ImportError:
    np = None
try:
    from PIL import Image
except ImportError:
    Image = None

# Get start time
task_start = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    pass

dimap_path = '/home/ga/snap_exports/vegetation_anomaly.dim'
data_dir = '/home/ga/snap_exports/vegetation_anomaly.data'
mask_tif = '/home/ga/snap_exports/stressed_mask.tif'

res = {
    'task_start': task_start,
    'dimap_exists': os.path.exists(dimap_path),
    'dimap_mtime': int(os.path.getmtime(dimap_path)) if os.path.exists(dimap_path) else 0,
    'mask_tif_exists': os.path.exists(mask_tif),
    'mask_tif_mtime': int(os.path.getmtime(mask_tif)) if os.path.exists(mask_tif) else 0,
    'bands': [],
    'z_score_mean': None,
    'z_score_std': None,
    'mask_unique_values': [],
    'numpy_available': np is not None
}

# 1. Parse DIMAP XML to verify bands
if res['dimap_exists']:
    try:
        tree = ET.parse(dimap_path)
        root = tree.getroot()
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                res['bands'].append(name_el.text.strip())
    except Exception as e:
        res['xml_error'] = str(e)

# 2. Math Proof: Read ENVI raster for Z-Score to verify mean~0 and std~1
if np is not None and os.path.exists(data_dir):
    z_img_path = None
    for f in os.listdir(data_dir):
        if ('z_score' in f.lower() or 'zscore' in f.lower()) and f.endswith('.img'):
            z_img_path = os.path.join(data_dir, f)
            break
    
    if z_img_path:
        hdr_path = z_img_path[:-4] + '.hdr'
        if os.path.exists(hdr_path):
            try:
                # Basic ENVI parsing
                dt = np.float32
                with open(hdr_path, 'r') as h:
                    for line in h:
                        if 'data type' in line.lower():
                            try:
                                code = line.split('=')[1].strip()
                                dt_map = {'1': np.uint8, '2': np.int16, '3': np.int32, '4': np.float32, '5': np.float64}
                                dt = dt_map.get(code, np.float32)
                            except:
                                pass
                
                data = np.fromfile(z_img_path, dtype=dt)
                valid_data = data[~np.isnan(data) & ~np.isinf(data)]
                if len(valid_data) > 0:
                    res['z_score_mean'] = float(np.mean(valid_data))
                    res['z_score_std'] = float(np.std(valid_data))
            except Exception as e:
                res['math_error'] = str(e)

# 3. Mask Validity: Read GeoTIFF mask
if res['mask_tif_exists'] and Image is not None and np is not None:
    try:
        img = Image.open(mask_tif)
        mask_data = np.array(img)
        valid_mask = mask_data[~np.isnan(mask_data) & ~np.isinf(mask_data)]
        unique_vals = np.unique(valid_mask).tolist()
        res['mask_unique_values'] = [float(v) for v in unique_vals]
    except Exception as e:
        res['mask_error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(res, f, indent=2)
EOF

# Ensure readable
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved:"
cat /tmp/task_result.json
echo "=== Export Complete ==="