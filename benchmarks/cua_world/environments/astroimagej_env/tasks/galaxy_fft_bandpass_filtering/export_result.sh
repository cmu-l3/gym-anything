#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Programmatically analyze the FITS file using astropy to verify filter application
python3 << PYEOF
import json
import os
import numpy as np

try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

raw_file = '/home/ga/AstroImages/raw/uit_galaxy_sample.fits'
out_file = '/home/ga/AstroImages/processed/uit_bandpass_filtered.fits'
report_file = '/home/ga/AstroImages/processed/filter_report.txt'

res = {
    'fits_exists': False,
    'fits_created_during_task': False,
    'report_exists': False,
    'report_content': '',
    'same_dimensions': False,
    'is_modified': False,
    'contrast_reduced': False,
    'raw_contrast': None,
    'out_contrast': None,
    'error': None
}

if os.path.exists(out_file):
    res['fits_exists'] = True
    mtime = os.path.getmtime(out_file)
    if mtime > int($TASK_START):
        res['fits_created_during_task'] = True
        
    if HAS_ASTROPY and os.path.exists(raw_file):
        try:
            raw_data = fits.getdata(raw_file).astype(float)
            out_data = fits.getdata(out_file).astype(float)
            
            # Handle multi-dimensional FITS if AIJ saved as 3D block
            if out_data.ndim > 2:
                out_data = out_data[0]
            if raw_data.ndim > 2:
                raw_data = raw_data[0]

            if raw_data.shape == out_data.shape:
                res['same_dimensions'] = True
                
                if not np.allclose(raw_data, out_data):
                    res['is_modified'] = True
                    
                # Calculate core vs edge contrast to detect spatial high-pass filtering.
                # A raw galaxy image has a massive central core glow compared to edges.
                # An FFT Bandpass filter suppressing large structures (>40 pixels) will flatten this gradient.
                cy, cx = raw_data.shape[0]//2, raw_data.shape[1]//2
                r = min(20, raw_data.shape[0]//4)
                
                # Use nanmedian to avoid extreme outliers
                raw_center = np.nanmedian(raw_data[cy-r:cy+r, cx-r:cx+r])
                raw_edge = np.nanmedian(raw_data[0:r, 0:r])
                
                out_center = np.nanmedian(out_data[cy-r:cy+r, cx-r:cx+r])
                out_edge = np.nanmedian(out_data[0:r, 0:r])
                
                # Shift both by their minimums to make them strictly positive for ratio computation
                raw_min = np.nanmin(raw_data)
                out_min = np.nanmin(out_data)
                
                raw_contrast = (raw_center - raw_min + 1) / (raw_edge - raw_min + 1)
                out_contrast = (out_center - out_min + 1) / (out_edge - out_min + 1)
                
                res['raw_contrast'] = float(raw_contrast)
                res['out_contrast'] = float(out_contrast)
                
                # A bandpass filter removing large structures will drastically lower the contrast ratio.
                if out_contrast < raw_contrast * 0.6:
                    res['contrast_reduced'] = True

        except Exception as e:
            res['error'] = str(e)

if os.path.exists(report_file):
    res['report_exists'] = True
    try:
        with open(report_file, 'r', encoding='utf-8', errors='ignore') as f:
            res['report_content'] = f.read()
    except Exception as e:
        res['error'] = str(e)

# Save result to JSON using safe temp file maneuver
with open('/tmp/task_result.json', 'w') as f:
    json.dump(res, f)
PYEOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="