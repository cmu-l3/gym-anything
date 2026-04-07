#!/bin/bash
echo "=== Exporting Clean Cosmic Rays task result ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

CLEAN_IMAGE="/home/ga/AstroImages/processed/wfpc2_clean.fits"
MASK_IMAGE="/home/ga/AstroImages/processed/cosmic_ray_mask.fits"

# Check file existence and modification times
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "true"
        else
            echo "false_old"
        fi
    else
        echo "false"
    fi
}

CLEAN_CREATED=$(check_file "$CLEAN_IMAGE")
MASK_CREATED=$(check_file "$MASK_IMAGE")

# Python script to analyze the FITS files directly inside the container
# This avoids needing astropy/scipy on the host verifier machine
cat > /tmp/analyze_fits.py << 'PYEOF'
import json
import os
import sys

# Default result dictionary
result = {
    "valid_fits": False,
    "clean_differs_from_orig": False,
    "pct_pixels_changed": 0.0,
    "correlation": 0.0,
    "math_correct": False,
    "math_mae": 99999.0,
    "error": None
}

try:
    import numpy as np
    from astropy.io import fits
    ASTROPY_AVAILABLE = True
except ImportError:
    ASTROPY_AVAILABLE = False
    result["error"] = "astropy or numpy not available"

if ASTROPY_AVAILABLE:
    orig_path = "/home/ga/AstroImages/raw/hst_wfpc2_sample.fits"
    clean_path = "/home/ga/AstroImages/processed/wfpc2_clean.fits"
    mask_path = "/home/ga/AstroImages/processed/cosmic_ray_mask.fits"
    
    def get_primary_data(filepath):
        if not os.path.exists(filepath):
            return None
        try:
            with fits.open(filepath) as hdul:
                for hdu in hdul:
                    if hdu.data is not None and len(hdu.data.shape) >= 2:
                        return hdu.data.astype(np.float32)
        except Exception:
            return None
        return None

    orig_data = get_primary_data(orig_path)
    clean_data = get_primary_data(clean_path)
    mask_data = get_primary_data(mask_path)
    
    if orig_data is not None and clean_data is not None:
        if orig_data.shape == clean_data.shape:
            result["valid_fits"] = True
            
            # Check how much was changed
            diff = orig_data - clean_data
            changed_mask = np.abs(diff) > 1e-4
            changed_pixels = np.sum(changed_mask)
            total_pixels = orig_data.size
            result["pct_pixels_changed"] = float(changed_pixels / total_pixels) if total_pixels > 0 else 0.0
            result["clean_differs_from_orig"] = bool(changed_pixels > 0)
            
            # Check correlation to ensure stars weren't obliterated (structure is preserved)
            orig_flat = orig_data.flatten()
            clean_flat = clean_data.flatten()
            std_orig = np.std(orig_flat)
            std_clean = np.std(clean_flat)
            
            if std_orig > 0 and std_clean > 0:
                corr = np.corrcoef(orig_flat, clean_flat)[0, 1]
                result["correlation"] = float(corr)
                
            # Check Math (Mask == Original - Cleaned)
            if mask_data is not None and mask_data.shape == orig_data.shape:
                expected_mask_1 = orig_data - clean_data
                expected_mask_2 = clean_data - orig_data
                
                mae1 = np.mean(np.abs(mask_data - expected_mask_1))
                mae2 = np.mean(np.abs(mask_data - expected_mask_2))
                
                min_mae = float(min(mae1, mae2))
                result["math_mae"] = min_mae
                
                # If mean absolute error is very small (< 1.0 out of typical 65535 or large float range), it's correct
                result["math_correct"] = bool(min_mae < 1.0)
        else:
            result["error"] = "Dimension mismatch between original and cleaned FITS"
    else:
        result["error"] = "Could not load FITS data for comparison"

print(json.dumps(result))
PYEOF

echo "Running FITS analysis..."
FITS_METRICS=$(python3 /tmp/analyze_fits.py 2>/dev/null || echo '{"error": "Failed to run analysis script"}')

# Combine all results into final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "clean_created": "$CLEAN_CREATED",
    "mask_created": "$MASK_CREATED",
    "fits_metrics": $FITS_METRICS
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export complete ==="