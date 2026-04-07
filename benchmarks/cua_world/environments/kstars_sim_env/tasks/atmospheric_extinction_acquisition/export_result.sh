#!/bin/bash
echo "=== Exporting atmospheric_extinction_acquisition results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Python script to process all FITS files and calculate true Altitude via Astropy
FITS_INFO=$(python3 -c "
import os, json, glob
from astropy.io import fits
from astropy.coordinates import SkyCoord, EarthLocation, AltAz
from astropy.time import Time
import astropy.units as u

base = '/home/ga/Images/extinction'
files = []
for pattern in [base + '/**/*.fits', base + '/**/*.fit']:
    for f in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(f)
            mtime = stat.st_mtime
            filt = ''
            exptime = -1.0
            lat, lon = 0.0, 0.0
            ra_str, dec_str = '0', '0'
            alt_deg = -999.0
            ra_deg, dec_deg = -999.0, -999.0

            with fits.open(f) as hdul:
                h = hdul[0].header
                filt = str(h.get('FILTER', h.get('FILTER2', '')))
                exptime = float(h.get('EXPTIME', -1))
                lat = float(h.get('SITELAT', 0))
                lon = float(h.get('SITELONG', 0))
                ra_str = str(h.get('OBJCTRA', '0'))
                dec_str = str(h.get('OBJCTDEC', '0'))

            try:
                # KStars/INDI sets OBJCTRA as 'HH MM SS' or 'HH:MM:SS'
                if ':' in ra_str or ' ' in ra_str:
                    c = SkyCoord(ra_str, dec_str, unit=(u.hourangle, u.deg))
                else:
                    c = SkyCoord(float(ra_str), float(dec_str), unit=(u.deg, u.deg))
                
                ra_deg = float(c.ra.degree)
                dec_deg = float(c.dec.degree)
                
                loc = EarthLocation(lat=lat*u.deg, lon=lon*u.deg)
                t = Time(mtime, format='unix')
                altaz = c.transform_to(AltAz(obstime=t, location=loc))
                alt_deg = float(altaz.alt.degree)
            except Exception as e:
                pass

            files.append({
                'name': os.path.basename(f),
                'dir': os.path.basename(os.path.dirname(f)),
                'size': stat.st_size,
                'mtime': mtime,
                'filter': filt,
                'exptime': exptime,
                'ra_deg': ra_deg,
                'dec_deg': dec_deg,
                'alt_deg': alt_deg
            })
        except Exception as e:
            pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

REPORT_PATH="/home/ga/Documents/extinction_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(cat "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="