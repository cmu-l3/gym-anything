#!/bin/bash
echo "=== Exporting empirical_bio_optical_spm_modeling result ==="

take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
take_screenshot /tmp/spm_modeling_end_screenshot.png

python3 << 'PYEOF'
import os, json, xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/spm_modeling_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'band_names': [],
    'virtual_bands': {},
    'total_band_count': 0,
    'has_ndti': False,
    'has_spm': False,
    'has_exceedance': False,
    'ndti_expression': '',
    'spm_expression': '',
    'exceedance_expression': '',
    'spm_tif_found': False,
    'spm_tif_created_after_start': False,
    'spm_tif_size': 0,
    'mask_tif_found': False,
    'mask_tif_created_after_start': False,
    'mask_tif_size': 0
}

# Search for .dim files
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim') and 'water_quality_model' in f:
                    dim_files.append(os.path.join(root, f))

# Fallback: any .dim created after start
if not dim_files:
    for d in search_dirs:
        if os.path.isdir(d):
            for root, dirs, files in os.walk(d):
                for f in files:
                    if f.endswith('.dim') and 'snap_data' not in root:
                        full = os.path.join(root, f)
                        if os.path.getmtime(full) > task_start:
                            dim_files.append(full)

ndti_kw = ['ndti', 'turbidity']
spm_kw = ['spm', 'mg_l', 'concentration']
mask_kw = ['exceedance', 'mask', 'limit']

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True

        tree = ET.parse(dim_file)
        root = tree.getroot()

        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                result['band_names'].append(bname)
                result['total_band_count'] += 1

                bl = bname.lower()
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                expr_text = ''
                if expr_el is not None and expr_el.text:
                    expr_text = expr_el.text.strip()
                    result['virtual_bands'][bname] = expr_text

                if any(kw in bl for kw in ndti_kw):
                    result['has_ndti'] = True
                    if expr_text: result['ndti_expression'] = expr_text
                
                if any(kw in bl for kw in spm_kw):
                    result['has_spm'] = True
                    if expr_text: result['spm_expression'] = expr_text

                if any(kw in bl for kw in mask_kw):
                    result['has_exceedance'] = True
                    if expr_text: result['exceedance_expression'] = expr_text

    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# Check TIF files
tif_dirs = ['/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga']
for d in tif_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.tif', '.tiff')) and 'snap_data' not in f:
                full = os.path.join(d, f)
                fsize = os.path.getsize(full)
                mtime = int(os.path.getmtime(full))
                
                if 'spm' in f.lower() or 'concentration' in f.lower():
                    result['spm_tif_found'] = True
                    if mtime > task_start: result['spm_tif_created_after_start'] = True
                    result['spm_tif_size'] = max(result['spm_tif_size'], fsize)
                
                if 'exceedance' in f.lower() or 'mask' in f.lower():
                    result['mask_tif_found'] = True
                    if mtime > task_start: result['mask_tif_created_after_start'] = True
                    result['mask_tif_size'] = max(result['mask_tif_size'], fsize)

# Fallback: if TIFs exist but names are wrong, just check if two TIFs were created
if not result['spm_tif_found'] or not result['mask_tif_found']:
    new_tifs = []
    for d in tif_dirs:
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.lower().endswith('.tif') and 'snap_data' not in f:
                    full = os.path.join(d, f)
                    if os.path.getmtime(full) > task_start:
                        new_tifs.append((full, os.path.getsize(full)))
    
    # Sort by size (mask should be smaller because binary vs float)
    new_tifs.sort(key=lambda x: x[1])
    if len(new_tifs) >= 2:
        if not result['mask_tif_found']:
            result['mask_tif_found'] = True
            result['mask_tif_created_after_start'] = True
            result['mask_tif_size'] = new_tifs[0][1]
        if not result['spm_tif_found']:
            result['spm_tif_found'] = True
            result['spm_tif_created_after_start'] = True
            result['spm_tif_size'] = new_tifs[-1][1]

with open('/tmp/spm_modeling_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

echo "=== Export Complete ==="