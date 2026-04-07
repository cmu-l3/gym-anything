#!/bin/bash
echo "=== Exporting veil_mosaic_survey results ==="

source /workspace/scripts/task_utils.sh

# ── 1. Take final screenshot ──────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── 2. Get current telescope position & filter ────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
CURRENT_FILTER=$(indi_getprop -1 "Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE" 2>/dev/null | tr -cd '0-9' | head -c 3)

if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi
if [ -z "$CURRENT_FILTER" ]; then CURRENT_FILTER="-1"; fi

# ── 3. Collect FITS metadata using Python ─────────────────────────────
BASE_DIR="/home/ga/Images/veil_mosaic"
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$BASE_DIR'
files = []
for pattern in [base + '/**/*.fits', base + '/**/*.fit']:
    for f in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(f)
            filt = ''
            ra_deg = -1.0
            dec_deg = -999.0
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    filt = str(h.get('FILTER', h.get('FILTER2', '')))
                    ra_str = str(h.get('OBJCTRA', h.get('RA', '')))
                    dec_str = str(h.get('OBJCTDEC', h.get('DEC', '')))
                    
                    if ra_str:
                        if ':' in ra_str or ' ' in ra_str:
                            p = ra_str.replace(':', ' ').split()
                            if len(p) >= 3:
                                ra_deg = (float(p[0]) + float(p[1])/60 + float(p[2])/3600) * 15.0
                        else:
                            ra_deg = float(ra_str)
                            
                    if dec_str:
                        sign = -1 if '-' in dec_str else 1
                        ds = dec_str.replace('-', '').replace(':', ' ').split()
                        if len(ds) >= 3:
                            dec_deg = sign * (float(ds[0]) + float(ds[1])/60 + float(ds[2])/3600)
                        else:
                            dec_deg = float(dec_str)
            except Exception as e: 
                pass
            
            parts = f.split('/')
            panel_dir = parts[-2] if len(parts) >= 2 else 'root'
            
            files.append({
                'name': os.path.basename(f),
                'panel_dir': panel_dir,
                'filter': filt,
                'ra_deg': ra_deg,
                'dec_deg': dec_deg,
                'size': stat.st_size,
                'mtime': stat.st_mtime
            })
        except Exception:
            pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 4. Check for log and sky preview ──────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

LOG_PATH="/home/ga/Documents/mosaic_log.txt"
LOG_EXISTS="false"
LOG_MTIME=0
LOG_B64=""
if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    LOG_B64=$(head -n 50 "$LOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

SKY_PREVIEW_EXISTS="false"
if [ -f "$BASE_DIR/sky_preview.png" ]; then
    SKY_MTIME=$(stat -c %Y "$BASE_DIR/sky_preview.png" 2>/dev/null || echo "0")
    if [ "$SKY_MTIME" -gt "$TASK_START" ]; then
        SKY_PREVIEW_EXISTS="true"
    fi
fi

# ── 5. Write to result JSON ───────────────────────────────────────────
LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")
SKY_PREVIEW_EXISTS_PY=$([ "$SKY_PREVIEW_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "current_filter_slot": $CURRENT_FILTER,
    "fits_files": $FITS_INFO,
    "log_exists": $LOG_EXISTS_PY,
    "log_mtime": $LOG_MTIME,
    "log_b64": "$LOG_B64",
    "sky_preview_exists": $SKY_PREVIEW_EXISTS_PY
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="