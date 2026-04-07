#!/bin/bash
echo "=== Setting up analyze_histogram task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure export directory exists and is clean
mkdir -p /home/ga/DICOM/exports
rm -f /home/ga/DICOM/exports/histogram_report.txt
chown -R ga:ga /home/ga/DICOM/exports

# Get a sample DICOM file (creates synthetic one if samples missing)
DICOM_FILE=$(get_sample_dicom)

if [ -z "$DICOM_FILE" ]; then
    echo "ERROR: No DICOM sample files found and fallback creation failed!"
    exit 1
fi
echo "Using DICOM file: $DICOM_FILE"

# Compute and store ground truth statistics (hidden from agent)
mkdir -p /tmp/ground_truth
python3 << PYEOF
import json, numpy as np, sys
try:
    import pydicom
    dcm_path = "$DICOM_FILE"
    ds = pydicom.dcmread(dcm_path)
    pixels = ds.pixel_array.astype(float)
    slope = float(getattr(ds, 'RescaleSlope', 1.0))
    intercept = float(getattr(ds, 'RescaleIntercept', 0.0))
    calibrated = pixels * slope + intercept
    
    stats = {
        "min": float(np.min(calibrated)),
        "max": float(np.max(calibrated)),
        "mean": float(np.mean(calibrated)),
        "file": dcm_path
    }
    with open("/tmp/ground_truth/pixel_stats.json", "w") as f:
        json.dump(stats, f, indent=2)
    print(f"Ground truth calculated: min={stats['min']:.1f}, max={stats['max']:.1f}, mean={stats['mean']:.1f}")
except Exception as e:
    print(f"Error computing ground truth: {e}")
PYEOF
chmod 700 /tmp/ground_truth

# Kill any existing Weasis processes
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for Weasis window
wait_for_weasis 60
sleep 2

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any first-run dialogs
dismiss_first_run_dialog
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_start.png

echo "=== Histogram analysis task setup complete ==="