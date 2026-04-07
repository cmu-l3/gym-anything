#!/bin/bash
echo "=== Exporting high_z_quasar_survey results ==="

source /workspace/scripts/task_utils.sh

# Take final proof screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect FITS file info robustly using Python 
FITS_INFO=$(python3 << 'PYEOF'
import os, json, glob

def parse_ra(val):
    if isinstance(val, float): return val
    try:
        if isinstance(val, str) and ' ' in val:
            p = val.split()
            return float(p[0]) + float(p[1])/60.0 + float(p[2])/3600.0
        return float(val)
    except: return -1.0

def parse_dec(val):
    if isinstance(val, float): return val
    try:
        if isinstance(val, str) and ' ' in val:
            p = val.split()
            sign = -1.0 if p[0].startswith('-') else 1.0
            return sign * (abs(float(p[0])) + float(p[1])/60.0 + float(p[2])/3600.0)
        return float(val)
    except: return -999.0

base = '/home/ga/Images/quasars'
files = []
for pattern in [base + '/**/*.fits', base + '/**/*.fit']:
    for f in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(f)
            ra = -1.0
            dec = -999.0
            filt = ''
            exptime = -1.0
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    ra = parse_ra(h.get('OBJCTRA', -1.0))
                    dec = parse_dec(h.get('OBJCTDEC', -999.0))
                    filt = str(h.get('FILTER', ''))
                    exptime = float(h.get('EXPTIME', -1.0))
            except: pass
            files.append({
                'path': f,
                'name': os.path.basename(f),
                'size': stat.st_size,
                'mtime': stat.st_mtime,
                'ra': ra,
                'dec': dec,
                'filter': filt,
                'exptime': exptime
            })
        except: pass
print(json.dumps(files))
PYEOF
)

# Collect PNG references
PNG_INFO=$(python3 << 'PYEOF'
import os, json, glob
base = '/home/ga/Images/quasars'
files = []
for f in glob.glob(base + '/**/*.png', recursive=True):
    try:
        stat = os.stat(f)
        files.append({
            'path': f,
            'name': os.path.basename(f),
            'size': stat.st_size,
            'mtime': stat.st_mtime
        })
    except: pass
print(json.dumps(files))
PYEOF
)

# Read survey log
LOG_PATH="/home/ga/Documents/quasar_survey_log.txt"
LOG_EXISTS="false"
LOG_MTIME=0
LOG_B64=""
if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    LOG_B64=$(head -n 50 "$LOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# Write final result JSON block
python3 << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "png_files": $PNG_INFO,
    "log_exists": "$LOG_EXISTS" == "true",
    "log_mtime": $LOG_MTIME,
    "log_b64": "$LOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="