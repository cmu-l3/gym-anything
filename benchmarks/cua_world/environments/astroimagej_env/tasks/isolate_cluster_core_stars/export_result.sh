#!/bin/bash
echo "=== Exporting Isolate Cluster Core Stars Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE parsing/closing
take_screenshot /tmp/task_end_screenshot.png

PROJECT_DIR="/home/ga/AstroImages/core_isolation"
OUTPUT_DIR="$PROJECT_DIR/output"
OUTPUT_FITS="$OUTPUT_DIR/m12_flattened.fits"
OUTPUT_CSV="$OUTPUT_DIR/measurements.csv"

# Alternative locations search
if [ ! -f "$OUTPUT_FITS" ]; then
    FITS_ALT=$(find /home/ga/AstroImages -type f \( -name "*flattened*.fits" -o -name "*flattened*.fit" \) | head -n 1)
    if [ -n "$FITS_ALT" ]; then OUTPUT_FITS="$FITS_ALT"; fi
fi

if [ ! -f "$OUTPUT_CSV" ]; then
    CSV_ALT=$(find /home/ga/AstroImages -type f \( -name "*measurements*.csv" -o -name "*.csv" \) | head -n 1)
    if [ -n "$CSV_ALT" ]; then OUTPUT_CSV="$CSV_ALT"; fi
fi

# Run Python script to extract image statistics
python3 << PYEOF
import json, os, csv
from astropy.io import fits
import numpy as np

fits_path = "$OUTPUT_FITS"
csv_path = "$OUTPUT_CSV"

res = {
    "fits_exists": os.path.exists(fits_path),
    "csv_exists": os.path.exists(csv_path),
    "csv_has_mean": False,
    "output_mean": None,
    "output_std": None,
    "output_core_median": None,
    "output_edge_median": None,
    "output_shape": None,
    "fits_path": fits_path,
    "csv_path": csv_path
}

if res["fits_exists"]:
    try:
        data = fits.getdata(fits_path)
        if data.ndim > 2:
            data = data[0]
        res["output_shape"] = list(data.shape)
        
        h, w = data.shape
        ch, cw = int(h*0.1), int(w*0.1)
        
        # Guard against zero dimension chunks just in case
        if ch > 0 and cw > 0:
            core = data[h//2 - ch//2 : h//2 + ch//2, w//2 - cw//2 : w//2 + cw//2]
            edges = np.concatenate([
                data[:ch, :cw].flatten(),
                data[:ch, -cw:].flatten(),
                data[-ch:, :cw].flatten(),
                data[-ch:, -cw:].flatten()
            ])
            
            res["output_mean"] = float(np.nanmean(data))
            res["output_std"] = float(np.nanstd(data))
            res["output_core_median"] = float(np.nanmedian(core))
            res["output_edge_median"] = float(np.nanmedian(edges))
    except Exception as e:
        res["fits_error"] = str(e)

if res["csv_exists"]:
    try:
        with open(csv_path, "r", encoding="utf-8", errors="ignore") as f:
            reader = csv.reader(f)
            headers = next(reader)
            if any("mean" in h.lower() for h in headers):
                res["csv_has_mean"] = True
            
            # Additional fallback content check
            f.seek(0)
            content = f.read()
            if "Mean" in content or "mean" in content:
                res["csv_has_mean"] = True
    except Exception as e:
        # Final fallback
        try:
            with open(csv_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                if "Mean" in content or "mean" in content:
                    res["csv_has_mean"] = True
        except:
            pass

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="