#!/bin/bash
echo "=== Exporting agn_blazar_outburst_monitoring results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 1. Get telescope position ─────────────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# ── 2. Collect FITS Info ──────────────────────────────────────────────
UPLOAD_DIR="/home/ga/Images/ToO/Mrk421"
FITS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$UPLOAD_DIR/**/*.fits', '$UPLOAD_DIR/**/*.fit', '$UPLOAD_DIR/*.fits', '$UPLOAD_DIR/*.fit']:
        for f in glob.glob(pattern, recursive=True):
            try:
                stat = os.stat(f)
                filt = ''
                exptime = -1
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        filt = str(h.get('FILTER', '')).strip()
                        exptime = float(h.get('EXPTIME', -1))
                except: pass
                files.append({
                    'name': os.path.basename(f),
                    'path': f,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'filter': filt,
                    'exptime': exptime
                })
            except: pass
except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 3. Check Context Image ────────────────────────────────────────────
CONTEXT_PATH="$UPLOAD_DIR/xray_context.png"
CONTEXT_EXISTS="false"
CONTEXT_MTIME=0
if [ -f "$CONTEXT_PATH" ]; then
    CONTEXT_EXISTS="true"
    CONTEXT_MTIME=$(stat -c %Y "$CONTEXT_PATH" 2>/dev/null || echo "0")
fi

# ── 4. Check ATel Response ────────────────────────────────────────────
RESPONSE_PATH="/home/ga/Documents/ATel_response.txt"
RESPONSE_EXISTS="false"
RESPONSE_MTIME=0
RESPONSE_B64=""
if [ -f "$RESPONSE_PATH" ]; then
    RESPONSE_EXISTS="true"
    RESPONSE_MTIME=$(stat -c %Y "$RESPONSE_PATH" 2>/dev/null || echo "0")
    RESPONSE_B64=$(head -n 50 "$RESPONSE_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# ── 5. Generate JSON ──────────────────────────────────────────────────
CONTEXT_EXISTS_PY=$([ "$CONTEXT_EXISTS" = "true" ] && echo "True" || echo "False")
RESPONSE_EXISTS_PY=$([ "$RESPONSE_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "context_exists": $CONTEXT_EXISTS_PY,
    "context_mtime": $CONTEXT_MTIME,
    "response_exists": $RESPONSE_EXISTS_PY,
    "response_mtime": $RESPONSE_MTIME,
    "response_b64": "$RESPONSE_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="