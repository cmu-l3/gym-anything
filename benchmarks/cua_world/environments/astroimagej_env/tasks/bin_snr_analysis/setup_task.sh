#!/bin/bash
echo "=== Setting up Bin SNR Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AstroImages/binning_analysis"
OUTPUT_DIR="$PROJECT_DIR/output"
rm -rf "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"

# Provide real HST NGC 6652 V-band FITS data
NGC_DIR="/opt/fits_samples/ngc6652"

python3 << 'PYEOF'
import os, shutil, glob, json
from astropy.io import fits
import numpy as np

NGC_DIR = "/opt/fits_samples/ngc6652"
PROJECT_DIR = "/home/ga/AstroImages/binning_analysis"
FITS_DEST = os.path.join(PROJECT_DIR, "ngc6652_555w.fits")

# Find the V-band (555nm) file
fits_files = glob.glob(os.path.join(NGC_DIR, "**/*.fits"), recursive=True) + \
             glob.glob(os.path.join(NGC_DIR, "**/*.fit"), recursive=True)

vband = None
for f in fits_files:
    if '555' in os.path.basename(f).lower():
        vband = f
        break
if not vband and fits_files:
    vband = fits_files[0]

if not vband:
    # If not found, create a placeholder structure so the script doesn't completely crash (though it should be there from environment setup)
    print("WARNING: FITS file not found. Environment may not be set up correctly.")
    raise FileNotFoundError("Missing NGC 6652 dataset.")

print(f"Using FITS file: {vband}")
shutil.copy2(vband, FITS_DEST)

# Load data to compute ground truth
data = fits.getdata(FITS_DEST).astype(float)
if data.ndim == 3:
    data = data[0]
elif data.ndim > 3:
    data = data.reshape(-1, data.shape[-1])[:data.shape[-2], :]

orig_h, orig_w = data.shape

# Select a relatively quiet background region
# Avoiding edges and obvious bright spots (WFPC2 chips often have a relatively quiet region around 100,100)
roi_x, roi_y, roi_w, roi_h = 100, 100, 120, 120

roi_data = data[roi_y:roi_y+roi_h, roi_x:roi_x+roi_w]
orig_mean = float(np.nanmean(roi_data))
orig_std = float(np.nanstd(roi_data))

# Bin 2x2 sum
shape2 = (orig_h//2, 2, orig_w//2, 2)
bin2 = data[:shape2[0]*2, :shape2[2]*2].reshape(shape2).sum(axis=-1).sum(axis=1)
roi2_data = bin2[roi_y//2:(roi_y+roi_h)//2, roi_x//2:(roi_x+roi_w)//2]
bin2_mean = float(np.nanmean(roi2_data))
bin2_std = float(np.nanstd(roi2_data))

# Bin 4x4 sum
shape4 = (orig_h//4, 4, orig_w//4, 4)
bin4 = data[:shape4[0]*4, :shape4[2]*4].reshape(shape4).sum(axis=-1).sum(axis=1)
roi4_data = bin4[roi_y//4:(roi_y+roi_h)//4, roi_x//4:(roi_x+roi_w)//4]
bin4_mean = float(np.nanmean(roi4_data))
bin4_std = float(np.nanstd(roi4_data))

# Save ROI coordinates for the user
roi_text = (
    f"Please measure the following background region:\n"
    f"X: {roi_x}\n"
    f"Y: {roi_y}\n"
    f"Width: {roi_w}\n"
    f"Height: {roi_h}\n\n"
    f"Note: When measuring binned images, remember to divide these coordinates by the bin factor!"
)
with open(os.path.join(PROJECT_DIR, "roi_region.txt"), "w") as f:
    f.write(roi_text)

# Save ground truth for the verifier
gt = {
    "orig_w": orig_w,
    "orig_h": orig_h,
    "orig_mean": orig_mean,
    "orig_std": orig_std,
    "bin2_w": orig_w // 2,
    "bin2_h": orig_h // 2,
    "bin2_mean": bin2_mean,
    "bin2_std": bin2_std,
    "bin4_w": orig_w // 4,
    "bin4_h": orig_h // 4,
    "bin4_mean": bin4_mean,
    "bin4_std": bin4_std,
    "expected_snr_improvement_2x2": (bin2_mean/bin2_std) / (orig_mean/orig_std) if orig_std > 0 and bin2_std > 0 else 2.0,
    "expected_snr_improvement_4x4": (bin4_mean/bin4_std) / (orig_mean/orig_std) if orig_std > 0 and bin4_std > 0 else 4.0
}
with open("/tmp/bin_snr_ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)

print("Ground truth pre-computed successfully.")
PYEOF

chown -R ga:ga "$PROJECT_DIR"
chmod 755 "$OUTPUT_DIR"

# Launch AstroImageJ (do not load the image, agent must do it)
echo "Launching AstroImageJ..."
launch_astroimagej 120

# Focus and maximize AstroImageJ
sleep 2
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot to document start state
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="