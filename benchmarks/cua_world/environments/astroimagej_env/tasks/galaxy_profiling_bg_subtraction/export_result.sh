#!/bin/bash
echo "=== Exporting Galaxy Profiling Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We will use Python inside the container to safely parse the FITS and CSV files
# This guarantees we extract metrics locally without depending on host astropy installation
cat > /tmp/extract_metrics.py << 'EOF'
import json
import os
import csv
import sys
import numpy as np

try:
    from astropy.io import fits
    ASTROPY_AVAILABLE = True
except ImportError:
    ASTROPY_AVAILABLE = False

def main():
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            task_start = float(f.read().strip())
    except:
        task_start = 0.0

    result = {
        "task_start": task_start,
        "bg_csv_exists": False,
        "bg_csv_recent": False,
        "bg_mean": None,
        "fits_exists": False,
        "fits_recent": False,
        "bitpix": None,
        "mean_diff": None,
        "std_diff": None,
        "profile_exists": False,
        "profile_recent": False,
        "profile_len": 0,
        "profile_max": None,
        "profile_min": None,
        "errors": []
    }

    # 1. Background CSV
    bg_csv_path = "/home/ga/AstroImages/measurements/background_measure.csv"
    if os.path.exists(bg_csv_path):
        result["bg_csv_exists"] = True
        result["bg_csv_recent"] = os.path.getmtime(bg_csv_path) > task_start
        try:
            with open(bg_csv_path, 'r', encoding='utf-8') as f:
                reader = csv.reader(f)
                headers = next(reader)
                mean_idx = -1
                for i, h in enumerate(headers):
                    if 'Mean' in h or 'mean' in h:
                        mean_idx = i
                        break
                if mean_idx != -1:
                    row = next(reader)
                    result["bg_mean"] = float(row[mean_idx])
        except Exception as e:
            result["errors"].append(f"BG CSV Error: {str(e)}")

    # 2. Subtracted FITS
    orig_fits = "/home/ga/AstroImages/raw/uit_galaxy_sample.fits"
    sub_fits = "/home/ga/AstroImages/processed/uit_galaxy_bg_subtracted.fits"
    if os.path.exists(sub_fits) and ASTROPY_AVAILABLE:
        result["fits_exists"] = True
        result["fits_recent"] = os.path.getmtime(sub_fits) > task_start
        try:
            with fits.open(sub_fits) as hdul_sub, fits.open(orig_fits) as hdul_orig:
                result["bitpix"] = hdul_sub[0].header.get('BITPIX', None)
                data_sub = hdul_sub[0].data.astype(float)
                data_orig = hdul_orig[0].data.astype(float)
                
                # Compare arrays only if shapes match
                if data_sub.shape == data_orig.shape:
                    diff = data_orig - data_sub
                    result["mean_diff"] = float(np.mean(diff))
                    result["std_diff"] = float(np.std(diff))
                else:
                    result["errors"].append("FITS shape mismatch")
        except Exception as e:
            result["errors"].append(f"FITS Error: {str(e)}")

    # 3. Profile CSV
    prof_csv_path = "/home/ga/AstroImages/measurements/galaxy_profile.csv"
    if os.path.exists(prof_csv_path):
        result["profile_exists"] = True
        result["profile_recent"] = os.path.getmtime(prof_csv_path) > task_start
        try:
            with open(prof_csv_path, 'r', encoding='utf-8') as f:
                reader = csv.reader(f)
                headers = next(reader)
                val_idx = 1 if len(headers) > 1 else 0
                vals = []
                for row in reader:
                    if row and len(row) > val_idx:
                        try:
                            vals.append(float(row[val_idx]))
                        except ValueError:
                            pass
                result["profile_len"] = len(vals)
                if vals:
                    result["profile_max"] = max(vals)
                    result["profile_min"] = min(vals)
        except Exception as e:
            result["errors"].append(f"Profile Error: {str(e)}")

    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f, indent=2)

if __name__ == "__main__":
    main()
EOF

# Run extraction
python3 /tmp/extract_metrics.py

# Ensure permissions are open for the verifier to copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Extracted results:"
cat /tmp/task_result.json

echo "=== Export complete ==="