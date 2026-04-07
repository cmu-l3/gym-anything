#!/bin/bash
set -euo pipefail

echo "=== Setting up Star Ellipticity Tracking Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
ASSESSMENT_DIR="/home/ga/AstroImages/tracking_assessment"
MEASUREMENT_DIR="/home/ga/AstroImages/measurements"

# Clean up any previous state
rm -rf "$ASSESSMENT_DIR" 2>/dev/null || true
mkdir -p "$ASSESSMENT_DIR" "$MEASUREMENT_DIR"

# Copy the real VLT FITS data
VLT_SOURCE="/opt/fits_samples/m12/Vcomb.fits"
if [ ! -f "$VLT_SOURCE" ]; then
    echo "ERROR: VLT data not found at $VLT_SOURCE. Ensure the environment is built correctly."
    # Create a fallback if missing so script doesn't completely fail
    touch "$ASSESSMENT_DIR/m12_Vcomb.fits"
else
    cp "$VLT_SOURCE" "$ASSESSMENT_DIR/m12_Vcomb.fits"
fi

# Create instructions reminder
cat > "$ASSESSMENT_DIR/instructions.txt" << 'EOF'
Tracking Quality Assessment Format Requirements

Output file: ~/AstroImages/measurements/tracking_quality_report.txt

Format:
# Tracking Quality Assessment - M12 VLT Vcomb
# Star measurements:
Star_ID  X_pixel  Y_pixel  FWHM_major  FWHM_minor  Ellipticity  PA_degrees
1        <x>      <y>      <maj>       <min>       <e>          <pa>
... (at least 5 stars)

# Summary:
Average_Ellipticity: <value>
Average_PA: <value>
Tracking_Quality: <GOOD|FAIR|POOR>

Thresholds:
GOOD: avg_e < 0.15
FAIR: 0.15 <= avg_e < 0.30
POOR: avg_e >= 0.30
EOF

# Ensure ownership
chown -R ga:ga "$ASSESSMENT_DIR" "$MEASUREMENT_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Calculate Ground Truth from the real image
echo "Calculating ground truth from real VLT image..."
python3 << 'PYEOF'
import os
import json
import numpy as np

fits_path = "/home/ga/AstroImages/tracking_assessment/m12_Vcomb.fits"
gt = {
    "image_width": 0,
    "image_height": 0,
    "avg_ellipticity": 0.05,  # Fallback default for VLT
    "avg_pa": 45.0,
    "tracking_quality": "GOOD"
}

try:
    from astropy.io import fits
    from scipy import ndimage
    
    if os.path.exists(fits_path):
        data = fits.getdata(fits_path).astype(float)
        if data.ndim == 3:
            data = data[0]
            
        gt["image_height"], gt["image_width"] = data.shape
        
        # Simple robust background
        bg = np.nanmedian(data)
        data_sub = data - bg
        
        # Find peaks
        smoothed = ndimage.gaussian_filter(data_sub, 2.0)
        thresh = np.percentile(smoothed, 99.8) # Top 0.2% pixels
        labeled, num_features = ndimage.label(smoothed > thresh)
        
        slices = ndimage.find_objects(labeled)
        ellipticities = []
        pas = []
        
        for sl in slices:
            if sl is None: continue
            patch = data_sub[sl]
            # Ensure patch is big enough but not huge
            if patch.shape[0] < 5 or patch.shape[1] < 5 or patch.shape[0] > 50:
                continue
                
            y, x = np.mgrid[0:patch.shape[0], 0:patch.shape[1]]
            m00 = np.sum(patch)
            if m00 <= 0: continue
            
            m10 = np.sum(x * patch) / m00
            m01 = np.sum(y * patch) / m00
            m20 = np.sum((x - m10)**2 * patch) / m00
            m02 = np.sum((y - m01)**2 * patch) / m00
            m11 = np.sum((x - m10) * (y - m01) * patch) / m00
            
            cov = np.array([[m20, m11], [m11, m02]])
            try:
                eigvals, eigvecs = np.linalg.eigh(cov)
                minor_var, major_var = np.sort(eigvals)
                if major_var > 0 and minor_var > 0:
                    ellipticity = 1.0 - np.sqrt(minor_var / major_var)
                    if 0 <= ellipticity < 1.0:
                        ellipticities.append(ellipticity)
            except:
                pass
                
        if ellipticities:
            # Use median to be robust against blends/cosmic rays
            gt["avg_ellipticity"] = float(np.median(ellipticities))
            
            if gt["avg_ellipticity"] < 0.15:
                gt["tracking_quality"] = "GOOD"
            elif gt["avg_ellipticity"] < 0.30:
                gt["tracking_quality"] = "FAIR"
            else:
                gt["tracking_quality"] = "POOR"
                
        print(f"Ground truth calculated: Ellipticity ~ {gt['avg_ellipticity']:.3f} ({gt['tracking_quality']})")
except Exception as e:
    print(f"Warning: Could not compute dynamic ground truth ({e}). Using robust defaults.")

with open("/tmp/tracking_ground_truth.json", "w") as f:
    json.dump(gt, f)
PYEOF

# Launch AstroImageJ (do NOT load the image - agent must do it)
echo "Launching AstroImageJ..."
launch_astroimagej 60

# Maximize AIJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="