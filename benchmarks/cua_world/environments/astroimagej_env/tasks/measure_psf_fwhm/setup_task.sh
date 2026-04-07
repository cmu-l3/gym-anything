#!/bin/bash
echo "=== Setting up PSF FWHM Measurement Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_timestamp

# Create project directory
PROJECT_DIR="/home/ga/AstroImages/psf_analysis"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Check if M12 V-band image exists
M12_SRC="/opt/fits_samples/m12/Vcomb.fits"
if [ ! -f "$M12_SRC" ]; then
    echo "ERROR: M12 V-band image not found at $M12_SRC"
    exit 1
fi

DEST_FITS="$PROJECT_DIR/m12_vband.fits"
cp "$M12_SRC" "$DEST_FITS"

# Process FITS and compute ground truth using Python
python3 << 'PYEOF'
import os, json
from astropy.io import fits
import numpy as np
from scipy import ndimage
from scipy.optimize import curve_fit

FITS_PATH = "/home/ga/AstroImages/psf_analysis/m12_vband.fits"
PLATE_SCALE = 0.25

# Read and update FITS header
with fits.open(FITS_PATH, mode='update') as hdul:
    hdr = hdul[0].header
    data = hdul[0].data
    
    # Add plate scale if not present
    if 'PLATESCL' not in hdr:
        hdr['PLATESCL'] = (PLATE_SCALE, 'Plate scale [arcsec/pixel]')
    else:
        PLATE_SCALE = hdr['PLATESCL']
        
    hdul.flush()

# Process data to find stars and measure ground truth FWHM
if data.ndim == 3:
    data = data[0]
elif data.ndim > 3:
    data = data.reshape(-1, data.shape[-1])[:data.shape[-2], :]

# Replace NaN with median
med = np.nanmedian(data)
data = np.where(np.isfinite(data), data, med)

# Smooth and threshold to find sources
smoothed = ndimage.gaussian_filter(data, sigma=2.0)
threshold = np.percentile(smoothed, 99.0)
binary = smoothed > threshold
labeled, num_features = ndimage.label(binary)

centroids = ndimage.center_of_mass(data, labeled, range(1, num_features + 1))

def gaussian_2d(xy, A, x0, y0, sigma_x, sigma_y, offset):
    x, y = xy
    g = offset + A * np.exp(-(((x - x0)**2 / (2 * sigma_x**2)) + ((y - y0)**2 / (2 * sigma_y**2))))
    return g.ravel()

fwhms = []
for cy, cx in centroids:
    iy, ix = int(round(cy)), int(round(cx))
    # Check if isolated (at least 20px from edge)
    if 20 < iy < data.shape[0] - 20 and 20 < ix < data.shape[1] - 20:
        cutout = data[iy-10:iy+11, ix-10:ix+11]
        
        # Check for multiple peaks (basic isolation check)
        cutout_smooth = ndimage.gaussian_filter(cutout, sigma=1.0)
        if np.sum(cutout_smooth > threshold) > 50: 
            x = np.arange(0, 21)
            y = np.arange(0, 21)
            X, Y = np.meshgrid(x, y)
            
            initial_guess = (np.max(cutout) - np.median(cutout), 10, 10, 2.0, 2.0, np.median(cutout))
            try:
                popt, _ = curve_fit(gaussian_2d, (X, Y), cutout.ravel(), p0=initial_guess, bounds=([0, 5, 5, 0.5, 0.5, 0], [np.inf, 15, 15, 10, 10, np.inf]))
                sigma_x, sigma_y = popt[3], popt[4]
                fwhm_x = 2.355 * sigma_x
                fwhm_y = 2.355 * sigma_y
                fwhm = (fwhm_x + fwhm_y) / 2.0
                if 1.0 < fwhm < 15.0:
                    fwhms.append(fwhm)
            except:
                pass

if len(fwhms) > 0:
    median_fwhm = float(np.median(fwhms))
else:
    median_fwhm = 4.5 # Fallback if fitting fails

gt = {
    "median_fwhm_pixels": median_fwhm,
    "plate_scale": PLATE_SCALE,
    "expected_fwhm_arcsec": median_fwhm * PLATE_SCALE,
    "num_stars_fitted": len(fwhms)
}

with open('/tmp/fwhm_ground_truth.json', 'w') as f:
    json.dump(gt, f)
PYEOF

# Create instructions file
cat > "$PROJECT_DIR/instructions.txt" << EOF
Task: Measure Stellar PSF FWHM and Determine Optimal Photometry Aperture

1. Examine m12_vband.fits.
2. Find at least 5 isolated, bright stars (avoid the crowded core).
3. Measure the FWHM (Full Width at Half Maximum) of each star using AstroImageJ tools (e.g., Plot Profile or Aperture Photometry tool readout).
4. Compute the mean FWHM in pixels.
5. Convert the mean FWHM to arcseconds using the plate scale (0.25 arcsec/pixel).
6. Recommend a photometry aperture radius (typically 2.5 * mean_FWHM_pixels).
7. Save your results to: fwhm_results.txt in this directory.

Format for fwhm_results.txt:
# PSF FWHM Measurement Results
# Star    X_pixel    Y_pixel    FWHM_pixels
Star1     <x1>       <y1>       <fwhm1>
Star2     <x2>       <y2>       <fwhm2>
...
# Summary
Mean_FWHM_pixels: <value>
Std_FWHM_pixels: <value>
Plate_scale_arcsec_per_pixel: 0.25
Mean_FWHM_arcsec: <value>
Recommended_aperture_radius_pixels: <value>
EOF

chown -R ga:ga "$PROJECT_DIR"

# Launch AstroImageJ and open image
MACRO_DIR="/home/ga/.astroimagej/macros"
mkdir -p "$MACRO_DIR"
chown -R ga:ga "/home/ga/.astroimagej"

LOAD_MACRO="/tmp/load_image.ijm"
cat > "$LOAD_MACRO" << 'MACROEOF'
open("/home/ga/AstroImages/psf_analysis/m12_vband.fits");
run("Enhance Contrast", "saturated=0.35");
MACROEOF
chmod 644 "$LOAD_MACRO"
chown ga:ga "$LOAD_MACRO"

# Kill existing instances
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

AIJ_PATH=""
for path in "/usr/local/bin/aij" "/opt/astroimagej/astroimagej/bin/AstroImageJ"; do
    if [ -x "$path" ]; then
        AIJ_PATH="$path"
        break
    fi
done

if [ -n "$AIJ_PATH" ]; then
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$AIJ_PATH' -macro '$LOAD_MACRO' > /tmp/astroimagej_ga.log 2>&1" &

    sleep 10
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "m12_vband"; then
            break
        fi
        sleep 1
    done

    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "AstroImageJ" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="