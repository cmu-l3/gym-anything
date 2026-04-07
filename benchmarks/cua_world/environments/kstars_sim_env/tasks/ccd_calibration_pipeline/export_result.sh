#!/bin/bash
echo "=== Exporting CCD Calibration Pipeline Results ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Extract metadata of the Flat frames using Python
FLATS_METADATA=$(python3 -c "
import os, json, glob

flats_dir = '/home/ga/Data/raw_flats'
files = []
for f in glob.glob(os.path.join(flats_dir, '*.fits')) + glob.glob(os.path.join(flats_dir, '*.fit')):
    try:
        stat = os.stat(f)
        filt = ''
        imagetyp = ''
        try:
            from astropy.io import fits as pyfits
            with pyfits.open(f) as hdul:
                h = hdul[0].header
                filt = str(h.get('FILTER', ''))
                imagetyp = str(h.get('IMAGETYP', h.get('FRAME', '')))
        except: pass
        files.append({
            'name': os.path.basename(f),
            'size': stat.st_size,
            'mtime': stat.st_mtime,
            'filter': filt,
            'imagetyp': imagetyp
        })
    except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 2. Extract metadata of the Calibrated frames
CALIBRATED_METADATA=$(python3 -c "
import os, json, glob

cal_dir = '/home/ga/Data/calibrated'
files = []
for f in glob.glob(os.path.join(cal_dir, '*.fits')) + glob.glob(os.path.join(cal_dir, '*.fit')):
    try:
        stat = os.stat(f)
        files.append({
            'name': os.path.basename(f),
            'size': stat.st_size,
            'mtime': stat.st_mtime
        })
    except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 3. Create JSON Result
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "flats": $FLATS_METADATA,
    "calibrated_files": $CALIBRATED_METADATA
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# 4. Tar the Data directory so the verifier can perform mathematical validation
echo "Archiving Data directory for array verification..."
cd /home/ga
tar -czf /tmp/data_export.tar.gz Data/ 2>/dev/null || true
chmod 666 /tmp/task_result.json /tmp/data_export.tar.gz 2>/dev/null || true

echo "Result files written to /tmp/task_result.json and /tmp/data_export.tar.gz"
echo "=== Export Complete ==="