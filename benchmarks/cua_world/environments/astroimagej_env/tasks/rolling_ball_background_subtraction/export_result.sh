#!/bin/bash
echo "=== Exporting Rolling Ball Background Subtraction task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot BEFORE any windows are closed
take_screenshot /tmp/task_end.png

OUTPUT_FITS="/home/ga/AstroImages/gradient_removal/output/Vcomb_flattened.fits"
REPORT_FILE="/home/ga/AstroImages/gradient_removal/output/background_report.txt"

# Analyze output FITS
python3 << 'PYEOF'
import json, os
import numpy as np
try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

output_fits = "/home/ga/AstroImages/gradient_removal/output/Vcomb_flattened.fits"
report_file = "/home/ga/AstroImages/gradient_removal/output/background_report.txt"

result = {
    "output_fits_exists": os.path.exists(output_fits),
    "report_file_exists": os.path.exists(report_file),
    "center_median": None,
    "corner_median": None,
    "gradient_diff": None,
    "overall_median": None,
    "report_content": ""
}

if result["report_file_exists"]:
    try:
        with open(report_file, "r") as f:
            result["report_content"] = f.read()[:2000]
    except Exception:
        pass

if result["output_fits_exists"] and HAS_ASTROPY:
    try:
        data = fits.getdata(output_fits).astype(float)
        if data.ndim == 3:
            data = data[0]
            
        h, w = data.shape
        cy, cx = h//2, w//2
        
        # Measure regions corresponding to the initial stats
        center_region = data[max(0, cy-100):min(h, cy+100), max(0, cx-100):min(w, cx+100)]
        corner_region = data[max(0, 50):min(h, 250), max(0, 50):min(w, 250)]
        
        result["center_median"] = float(np.nanmedian(center_region))
        result["corner_median"] = float(np.nanmedian(corner_region))
        result["overall_median"] = float(np.nanmedian(data))
        result["gradient_diff"] = abs(result["center_median"] - result["corner_median"])
        
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Check anti-gaming timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
if [ -f "$OUTPUT_FITS" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FITS" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        python3 -c "import json; d=json.load(open('/tmp/task_result.json')); d['file_created_during_task'] = True; json.dump(d, open('/tmp/task_result.json', 'w'))"
    else
        python3 -c "import json; d=json.load(open('/tmp/task_result.json')); d['file_created_during_task'] = False; json.dump(d, open('/tmp/task_result.json', 'w'))"
    fi
else
    python3 -c "import json; d=json.load(open('/tmp/task_result.json')); d['file_created_during_task'] = False; json.dump(d, open('/tmp/task_result.json', 'w'))"
fi

echo "Exported Result:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="