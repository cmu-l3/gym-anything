#!/bin/bash
echo "=== Exporting task results ==="

export TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
export TASK_END=$(date +%s)

# Take a final environmental screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script inside the container to calculate metrics securely
# This ensures astropy and scipy are available and we don't have to transfer the heavy FITS to the host.
cat > /tmp/validate_profile.py << 'EOF'
import os, json, csv
import numpy as np
from astropy.io import fits
from scipy.ndimage import gaussian_filter

agent_csv = "/home/ga/AstroImages/measurements/shock_profile.csv"
fits_file = "/home/ga/AstroImages/raw/673nmos.fits"

result = {
    "csv_exists": False,
    "csv_rows": 0,
    "correlation_raw": 0.0,
    "correlation_blurred_best": 0.0,
    "tv_agent": 0.0,
    "tv_gt_raw": 0.0,
    "tv_gt_blurred": 0.0,
    "screenshot_exists": os.path.exists("/home/ga/AstroImages/measurements/plot_screenshot.png"),
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "error": None
}

if os.path.exists(agent_csv):
    result["csv_exists"] = True
    try:
        # Parse the agent's CSV
        with open(agent_csv, 'r') as f:
            reader = csv.reader(f)
            lines = list(reader)

        # ImageJ's Plot Profile outputs 'Distance' and 'Gray_Value' or similar
        vals = []
        for row in lines:
            if len(row) >= 2:
                try:
                    vals.append(float(row[-1]))
                except ValueError:
                    pass
        result["csv_rows"] = len(vals)

        if len(vals) > 0 and os.path.exists(fits_file):
            agent_profile = np.array(vals)
            # Total Variation (smoothness measure)
            result["tv_agent"] = float(np.sum(np.abs(np.diff(agent_profile))))

            with fits.open(fits_file) as hdul:
                data = hdul[0].data

            H, W = data.shape
            
            # Ground Truth Slice: ImageJ Y=600 is row 600 from top.
            slice_raw = data[600:700, 400:800]
            prof_raw = np.nanmean(slice_raw, axis=0)
            result["tv_gt_raw"] = float(np.sum(np.abs(np.diff(prof_raw))))

            # Ground Truth Slice Blurred (Gaussian Sigma=3.0)
            data_blurred = gaussian_filter(data, sigma=3.0)
            slice_blur = data_blurred[600:700, 400:800]
            prof_blur = np.mean(slice_blur, axis=0)
            result["tv_gt_blurred"] = float(np.sum(np.abs(np.diff(prof_blur))))

            # Backup calculation in case FITS reader inverted the Y-axis
            slice_blur_inverted = data_blurred[H-700:H-600, 400:800]
            prof_blur_inverted = np.mean(slice_blur_inverted, axis=0)

            if len(agent_profile) == 400:
                r_raw = np.corrcoef(agent_profile, prof_raw)[0, 1]
                r_blur_std = np.corrcoef(agent_profile, prof_blur)[0, 1]
                r_blur_inv = np.corrcoef(agent_profile, prof_blur_inverted)[0, 1]
                
                result["correlation_raw"] = float(np.nan_to_num(r_raw))
                result["correlation_blurred_best"] = float(max(np.nan_to_num(r_blur_std), np.nan_to_num(r_blur_inv)))
            else:
                # Correlate available overlap if lengths mismatch
                min_len = min(len(agent_profile), len(prof_blur))
                if min_len > 100:
                    r_blur_partial = np.corrcoef(agent_profile[:min_len], prof_blur[:min_len])[0, 1]
                    result["correlation_blurred_best"] = float(np.nan_to_num(r_blur_partial))
    except Exception as e:
        result["error"] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /tmp/validate_profile.py

# Ensure accessibility to verifier
chmod 666 /tmp/task_result.json
echo "=== Export complete ==="