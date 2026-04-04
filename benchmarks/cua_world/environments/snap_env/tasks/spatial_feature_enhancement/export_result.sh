#!/bin/bash
echo "=== Exporting spatial_feature_enhancement result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/spatial_feature_enhancement_end_screenshot.png

python3 << 'PYEOF'
import os, json, xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/spatial_feature_enhancement_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'band_names': [],
    'total_band_count': 0,
    'original_band_count': 3,
    'has_filtered_band': False,
    'filtered_band_names': [],
    'original_bands_preserved': False,
    'filter_type_detected': '',
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

# Keywords that indicate a spatial filter was applied
filter_keywords = ['filter', 'edge', 'sharp', 'smooth', 'blur', 'laplace',
                   'sobel', 'prewitt', 'gradient', 'highpass', 'high_pass',
                   'lowpass', 'low_pass', 'median', 'mean', 'gauss',
                   'convolv', 'kernel', 'enhance', 'detect']

# Search for .dim files
search_dirs = ['/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim'):
                    full = os.path.join(root, f)
                    if 'snap_data' in full:
                        continue
                    dim_files.append(full)

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        file_bands = []
        original_found = 0

        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                file_bands.append(bname)
                result['band_names'].append(bname)
                result['total_band_count'] += 1

                bl = bname.lower()

                # Check if this looks like a filtered band
                if any(kw in bl for kw in filter_keywords):
                    result['has_filtered_band'] = True
                    result['filtered_band_names'].append(bname)
                    # Try to identify filter type
                    for kw in ['edge', 'laplace', 'sobel', 'prewitt',
                               'highpass', 'high_pass', 'sharp',
                               'lowpass', 'low_pass', 'mean', 'median',
                               'gauss', 'smooth', 'blur']:
                        if kw in bl:
                            result['filter_type_detected'] = kw
                            break

                # Check if this is an original band (band_1, band_2, band_3)
                if bl in ['band_1', 'band_2', 'band_3', 'red', 'green', 'blue']:
                    original_found += 1

        # If we have more bands than original, some must be filtered
        if len(file_bands) > result['original_band_count']:
            if not result['has_filtered_band']:
                # Extra bands exist but names don't match filter keywords
                # Still count as filtered since they are additional bands
                extra = [b for b in file_bands
                         if b.lower() not in ['band_1', 'band_2', 'band_3',
                                              'red', 'green', 'blue']]
                if extra:
                    result['has_filtered_band'] = True
                    result['filtered_band_names'] = extra

        # Check original bands preserved
        if original_found >= 2:
            result['original_bands_preserved'] = True

    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# Search for GeoTIFF exports
tif_dirs = ['/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga']
for d in tif_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.tif', '.tiff')):
                full = os.path.join(d, f)
                if 'snap_data' in full:
                    continue
                fsize = os.path.getsize(full)
                mtime = int(os.path.getmtime(full))
                if mtime > task_start and fsize > result['tif_file_size']:
                    result['tif_found'] = True
                    result['tif_created_after_start'] = True
                    result['tif_file_size'] = fsize

with open('/tmp/spatial_feature_enhancement_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/spatial_feature_enhancement_result.json")
PYEOF

echo "=== Export Complete ==="
