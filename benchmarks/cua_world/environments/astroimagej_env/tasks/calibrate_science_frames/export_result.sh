#!/bin/bash
echo "=== Exporting CCD Calibration Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

PROJECT_DIR="/home/ga/AstroImages/calibration_project"
REDUCED_DIR="$PROJECT_DIR/reduced"

# Analyze results using Python
python3 << 'PYEOF'
import json
import os
import glob
import sys

try:
    from astropy.io import fits
    import numpy as np
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

PROJECT = "/home/ga/AstroImages/calibration_project"
REDUCED = f"{PROJECT}/reduced"

result = {
    "master_bias_found": False,
    "master_dark_found": False,
    "master_flat_found": False,
    "calibrated_frames_found": 0,
    "master_bias_mean": None,
    "master_bias_std": None,
    "master_dark_mean": None,
    "master_flat_mean": None,
    "master_flat_min": None,
    "master_flat_max": None,
    "cal_science_means": [],
    "raw_science_mean": None,
    "total_output_files": 0,
    "reduced_dir_exists": os.path.isdir(REDUCED),
    "any_output_anywhere": False,
}

# Check for output files in reduced/ and also anywhere under project dir
all_fits_reduced = glob.glob(f"{REDUCED}/*.fits") + glob.glob(f"{REDUCED}/*.fit")
result["total_output_files"] = len(all_fits_reduced)

# Also check common alternative locations
alt_locations = [
    "/home/ga/AstroImages/",
    "/home/ga/Desktop/",
    "/home/ga/",
    "/tmp/",
]
for loc in alt_locations:
    alt_files = glob.glob(f"{loc}/*master*", recursive=False) + \
                glob.glob(f"{loc}/*cal_*", recursive=False)
    if alt_files:
        result["any_output_anywhere"] = True
        result["alt_output_location"] = loc
        break

if not HAS_ASTROPY:
    # Fallback: just check file existence
    for pattern in ["*bias*", "*master_bias*", "*mbias*"]:
        if glob.glob(f"{REDUCED}/{pattern}"):
            result["master_bias_found"] = True
            break
    for pattern in ["*dark*", "*master_dark*", "*mdark*"]:
        if glob.glob(f"{REDUCED}/{pattern}"):
            result["master_dark_found"] = True
            break
    for pattern in ["*flat*", "*master_flat*", "*mflat*"]:
        if glob.glob(f"{REDUCED}/{pattern}"):
            result["master_flat_found"] = True
            break
    cal_patterns = glob.glob(f"{REDUCED}/cal_*") + glob.glob(f"{REDUCED}/*calibrated*")
    result["calibrated_frames_found"] = len(cal_patterns)
else:
    # Full analysis with astropy
    def find_file(directory, patterns):
        """Find a FITS file matching any of the patterns."""
        for p in patterns:
            matches = glob.glob(f"{directory}/{p}")
            if matches:
                return matches[0]
        return None

    def analyze_fits(filepath):
        """Read FITS and return basic statistics."""
        try:
            with fits.open(filepath) as hdul:
                data = hdul[0].data
                if data is not None:
                    return {
                        "mean": float(np.nanmean(data)),
                        "std": float(np.nanstd(data)),
                        "min": float(np.nanmin(data)),
                        "max": float(np.nanmax(data)),
                        "shape": list(data.shape),
                    }
        except Exception as e:
            print(f"Error reading {filepath}: {e}", file=sys.stderr)
        return None

    # Check master bias
    bias_file = find_file(REDUCED, ["*bias*.fits", "*bias*.fit", "*mbias*", "master_bias*"])
    if bias_file:
        result["master_bias_found"] = True
        stats = analyze_fits(bias_file)
        if stats:
            result["master_bias_mean"] = stats["mean"]
            result["master_bias_std"] = stats["std"]
            result["master_bias_shape"] = stats["shape"]

    # Check master dark
    dark_file = find_file(REDUCED, ["*dark*.fits", "*dark*.fit", "*mdark*", "master_dark*"])
    if dark_file:
        result["master_dark_found"] = True
        stats = analyze_fits(dark_file)
        if stats:
            result["master_dark_mean"] = stats["mean"]

    # Check master flat
    flat_file = find_file(REDUCED, ["*flat*.fits", "*flat*.fit", "*mflat*", "master_flat*"])
    if flat_file:
        result["master_flat_found"] = True
        stats = analyze_fits(flat_file)
        if stats:
            result["master_flat_mean"] = stats["mean"]
            result["master_flat_min"] = stats["min"]
            result["master_flat_max"] = stats["max"]

    # Check calibrated science frames
    cal_files = sorted(
        glob.glob(f"{REDUCED}/cal_*.fits") +
        glob.glob(f"{REDUCED}/cal_*.fit") +
        glob.glob(f"{REDUCED}/*calibrated*.fits") +
        glob.glob(f"{REDUCED}/*calibrated*.fit")
    )
    result["calibrated_frames_found"] = len(cal_files)
    for cf in cal_files:
        stats = analyze_fits(cf)
        if stats:
            result["cal_science_means"].append(stats["mean"])

    # Get raw science frame stats for comparison
    sci_dir = f"{PROJECT}/science"
    raw_files = sorted(glob.glob(f"{sci_dir}/*.fits"))
    if raw_files:
        stats = analyze_fits(raw_files[0])
        if stats:
            result["raw_science_mean"] = stats["mean"]

# Load and embed ground truth for the verifier
gt_path = "/tmp/calibration_ground_truth.json"
if os.path.exists(gt_path):
    with open(gt_path) as f:
        result["ground_truth"] = json.load(f)

# Close AstroImageJ
os.system("pkill -f 'astroimagej\\|aij\\|AstroImageJ' 2>/dev/null")

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Export complete")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
