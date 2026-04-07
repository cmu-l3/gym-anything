#!/bin/bash
echo "=== Exporting tno_astrometric_recovery results ==="

source /workspace/scripts/task_utils.sh

# ── 1. Take final screenshot ──────────────────────────────────────────
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 2. Collect FITS Info & Extract Headers via Python ─────────────────
# We use Python and Astropy to read the exact RA/Dec coordinates embedded
# in the FITS headers by the CCD Simulator to cryptographically prove
# the agent slewed to the correct coordinates before taking the exposure.
FITS_INFO=$(python3 -c "
import os, json, glob

try:
    from astropy.io import fits as pyfits
    from astropy.coordinates import SkyCoord
    import astropy.units as u
    ASTROPY_AVAIL = True
except ImportError:
    ASTROPY_AVAIL = False

base = '/home/ga/Images/tno_recovery'
targets = ['Eris', 'Makemake', 'Haumea']
files = []

for target in targets:
    d = os.path.join(base, target)
    for pattern in [d + '/*.fits', d + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                filt, exptime = '', -1
                ra_deg, dec_deg = -1.0, -999.0
                
                if ASTROPY_AVAIL:
                    try:
                        with pyfits.open(f) as hdul:
                            h = hdul[0].header
                            filt = str(h.get('FILTER', h.get('FILTER2', '')))
                            exptime = float(h.get('EXPTIME', -1))
                            ra_str = str(h.get('OBJCTRA', ''))
                            dec_str = str(h.get('OBJCTDEC', ''))
                            
                            if ra_str and dec_str:
                                c = SkyCoord(ra_str, dec_str, unit=(u.hourangle, u.deg))
                                ra_deg = c.ra.deg
                                dec_deg = c.dec.deg
                    except Exception as e:
                        pass
                
                files.append({
                    'name': os.path.basename(f),
                    'target': target,
                    'path': f,
                    'filter': filt,
                    'exptime': exptime,
                    'ra_deg': ra_deg,
                    'dec_deg': dec_deg,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except: pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 3. Check for Sky Capture ──────────────────────────────────────────
SKY_CAPTURE_EXISTS="false"
SKY_CAPTURE_MTIME=0
SKY_CAPTURE_SIZE=0
if [ -f "/home/ga/Images/tno_recovery/makemake_field.png" ]; then
    SKY_CAPTURE_MTIME=$(stat -c %Y "/home/ga/Images/tno_recovery/makemake_field.png" 2>/dev/null || echo "0")
    if [ "$SKY_CAPTURE_MTIME" -gt "$TASK_START" ]; then
        SKY_CAPTURE_EXISTS="true"
        SKY_CAPTURE_SIZE=$(stat -c %s "/home/ga/Images/tno_recovery/makemake_field.png" 2>/dev/null || echo "0")
    fi
fi

# ── 4. Check for Summary Report ───────────────────────────────────────
REPORT_PATH="/home/ga/Documents/tno_recovery_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_CONTENT_B64=$(head -n 100 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# ── 5. Write Result JSON ──────────────────────────────────────────────
SKY_CAPTURE_EXISTS_PY=$([ "$SKY_CAPTURE_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "sky_capture_exists": $SKY_CAPTURE_EXISTS_PY,
    "sky_capture_size": $SKY_CAPTURE_SIZE,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_content_b64": "$REPORT_CONTENT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="