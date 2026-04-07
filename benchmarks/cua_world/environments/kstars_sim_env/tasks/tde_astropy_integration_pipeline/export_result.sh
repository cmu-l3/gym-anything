#!/bin/bash
echo "=== Exporting tde_astropy_integration_pipeline results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

TARGET_DIR="/home/ga/Images/tde_monitoring/asassn14li"

# 1. Collect FITS metadata and generate Ground Truth Summary via Astropy
# (We run this inside the container to ensure accurate interpretation of the files)
python3 - << 'PYEOF'
import os
import json
import glob

target_dir = "/home/ga/Images/tde_monitoring/asassn14li"
fits_info = []
ground_truth_summary = {}

try:
    from astropy.io import fits
    has_astropy = True
except ImportError:
    has_astropy = False

for f in glob.glob(os.path.join(target_dir, "*.fits")):
    try:
        stat = os.stat(f)
        filt = ""
        exptime = 0.0
        
        if has_astropy:
            with fits.open(f) as hdul:
                h = hdul[0].header
                filt = str(h.get('FILTER', '')).strip()
                exptime = float(h.get('EXPTIME', 0.0))
                
                if filt:
                    ground_truth_summary[filt] = ground_truth_summary.get(filt, 0.0) + exptime
                    
        fits_info.append({
            'name': os.path.basename(f),
            'size': stat.st_size,
            'mtime': stat.st_mtime,
            'filter': filt,
            'exptime': exptime
        })
    except Exception as e:
        pass

with open('/tmp/ground_truth_summary.json', 'w') as f:
    json.dump(ground_truth_summary, f)
    
with open('/tmp/fits_info.json', 'w') as f:
    json.dump(fits_info, f)
PYEOF

FITS_INFO=$(cat /tmp/fits_info.json 2>/dev/null || echo "[]")
GROUND_TRUTH_JSON=$(cat /tmp/ground_truth_summary.json 2>/dev/null || echo "{}")

# 2. Check Agent's JSON Output
AGENT_JSON_PATH="/home/ga/Documents/integration_summary.json"
AGENT_JSON_EXISTS="false"
AGENT_JSON_CONTENT="{}"

if [ -f "$AGENT_JSON_PATH" ]; then
    AGENT_JSON_EXISTS="true"
    # Ensure it's valid JSON before embedding
    if python3 -c "import json; json.load(open('$AGENT_JSON_PATH'))" 2>/dev/null; then
        AGENT_JSON_CONTENT=$(cat "$AGENT_JSON_PATH")
    else
        AGENT_JSON_CONTENT="{\"error\": \"invalid_json\"}"
    fi
fi

# 3. Check Sky View Image
SKY_EXISTS="false"
SKY_SIZE="0"
if [ -f "$TARGET_DIR/sky_view.png" ]; then
    SKY_MTIME=$(stat -c %Y "$TARGET_DIR/sky_view.png" 2>/dev/null || echo "0")
    if [ "$SKY_MTIME" -gt "$TASK_START" ]; then
        SKY_EXISTS="true"
        SKY_SIZE=$(stat -c %s "$TARGET_DIR/sky_view.png" 2>/dev/null || echo "0")
    fi
fi

# 4. Construct Final Result Object
SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")
AGENT_JSON_EXISTS_PY=$([ "$AGENT_JSON_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "sky_capture_exists": $SKY_EXISTS_PY,
    "sky_capture_size": $SKY_SIZE,
    "agent_json_exists": $AGENT_JSON_EXISTS_PY,
    "agent_json_content": $AGENT_JSON_CONTENT,
    "ground_truth_summary": $GROUND_TRUTH_JSON
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="