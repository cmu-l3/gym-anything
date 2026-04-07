#!/bin/bash
echo "=== Exporting spectral_variance_anomaly_report result ==="

# Fallback screenshot function if task_utils isn't present
take_screenshot() {
    DISPLAY=:1 scrot "$1" 2>/dev/null || DISPLAY=:1 import -window root "$1" 2>/dev/null || true
}

take_screenshot /tmp/task_end_screenshot.png

python3 << 'PYEOF'
import os, json
import xml.etree.ElementTree as ET

result = {
    'task_start': 0,
    'dim_found': False,
    'dim_bands': [],
    'has_mean': False,
    'has_variance': False,
    'has_anomaly': False,
    'tif_found': False,
    'tif_size': 0,
    'tif_binary': False,
    'report_found': False,
    'report_content': "",
    'report_numbers': [],
    'gt_computed': False
}

ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    try:
        result['task_start'] = int(open(ts_file).read().strip())
    except:
        pass

# Check DIMAP file
dim_path = '/home/ga/snap_exports/landsat_qa.dim'
if os.path.exists(dim_path):
    result['dim_found'] = True
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip().lower()
                result['dim_bands'].append(bname)
                if 'mean' in bname: result['has_mean'] = True
                if 'var' in bname: result['has_variance'] = True
                if 'anomal' in bname or 'flag' in bname or 'mask' in bname:
                    result['has_anomaly'] = True
    except Exception as e:
        print(f"Error parsing dim: {e}")

# Check TIF file
tif_path = '/home/ga/snap_exports/anomaly_mask.tif'
if os.path.exists(tif_path):
    result['tif_found'] = True
    result['tif_size'] = os.path.getsize(tif_path)
    
    # Check if binary content
    try:
        from PIL import Image
        import numpy as np
        img = Image.open(tif_path)
        arr = np.array(img)
        unique_vals = np.unique(arr)
        if len(unique_vals) <= 3 and set(unique_vals).issubset({0, 1, 255}):
            result['tif_binary'] = True
        elif len(unique_vals) <= 2:
            result['tif_binary'] = True
    except:
        pass

# Check Quality Report
report_path = '/home/ga/snap_exports/quality_report.txt'
if os.path.exists(report_path):
    result['report_found'] = True
    try:
        with open(report_path, 'r') as f:
            content = f.read()
            result['report_content'] = content
            import re
            nums = re.findall(r"[-+]?\d*\.\d+|\d+", content)
            result['report_numbers'] = [float(n) for n in nums]
    except:
        pass

# Try to compute ground truth values
try:
    import numpy as np
    data_file = '/home/ga/snap_data/landsat_multispectral.tif'
    computed = False
    
    # CV2 approach
    try:
        import cv2
        img = cv2.imread(data_file, cv2.IMREAD_UNCHANGED)
        if img is not None and len(img.shape) == 3 and img.shape[2] >= 4:
            stacked = img[:,:,:4].astype(float)
            mean_band = np.mean(stacked, axis=2)
            var_band = np.mean((stacked - np.expand_dims(mean_band, 2))**2, axis=2)
            anomaly = (var_band > 5000).astype(int)
            result['gt_total_pixels'] = int(anomaly.size)
            result['gt_anomalous_pixels'] = int(np.sum(anomaly))
            result['gt_anomalous_fraction'] = float(np.sum(anomaly)) / anomaly.size
            result['gt_computed'] = True
            computed = True
    except:
        pass

    # PIL approach if cv2 fails
    if not computed:
        from PIL import Image
        img = Image.open(data_file)
        bands = []
        for i in range(img.n_frames if hasattr(img, 'n_frames') else 1):
            img.seek(i)
            bands.append(np.array(img).astype(float))
        
        if len(bands) == 1 and len(bands[0].shape) == 3 and bands[0].shape[2] >= 4:
            stacked = bands[0][:,:,:4]
            mean_band = np.mean(stacked, axis=2)
            var_band = np.mean((stacked - np.expand_dims(mean_band, 2))**2, axis=2)
            anomaly = (var_band > 5000).astype(int)
            result['gt_total_pixels'] = int(anomaly.size)
            result['gt_anomalous_pixels'] = int(np.sum(anomaly))
            result['gt_anomalous_fraction'] = float(np.sum(anomaly)) / anomaly.size
            result['gt_computed'] = True
        elif len(bands) >= 4:
            stacked = np.stack(bands[:4], axis=0)
            mean_band = np.mean(stacked, axis=0)
            var_band = np.mean((stacked - mean_band)**2, axis=0)
            anomaly = (var_band > 5000).astype(int)
            result['gt_total_pixels'] = int(anomaly.size)
            result['gt_anomalous_pixels'] = int(np.sum(anomaly))
            result['gt_anomalous_fraction'] = float(np.sum(anomaly)) / anomaly.size
            result['gt_computed'] = True

except Exception as e:
    print(f"Failed to compute GT: {e}")

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="