#!/bin/bash
set -e
echo "=== Setting up Top Bright Stars task ==="

source /workspace/scripts/task_utils.sh

# Create project directory
PROJECT_DIR="/home/ga/AstroImages/ngc6652_project"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Copy the real HST F814W image
NGC_DIR="/opt/fits_samples/ngc6652"
if [ ! -f "$NGC_DIR/814wmos.fits" ]; then
    echo "F814W FITS file not found, unzipping..."
    unzip -q -o "$NGC_DIR/814wmos.zip" -d "$NGC_DIR" || true
fi

FITS_SRC="$NGC_DIR/814wmos.fits"
if [ ! -f "$FITS_SRC" ]; then
    echo "ERROR: Failed to locate F814W FITS file!"
    exit 1
fi

FITS_DEST="$PROJECT_DIR/ngc6652_814w.fits"
cp "$FITS_SRC" "$FITS_DEST"
chown ga:ga "$FITS_DEST"
chmod 644 "$FITS_DEST"

# ============================================================
# Compute Ground Truth dynamically from the real image
# ============================================================
echo "Computing ground truth from real image data..."
python3 << 'PYEOF'
import os
import json
import numpy as np
from astropy.io import fits
from scipy import ndimage

FITS_FILE = "/home/ga/AstroImages/ngc6652_project/ngc6652_814w.fits"
GT_FILE = "/tmp/bright_stars_ground_truth.json"

try:
    with fits.open(FITS_FILE) as hdul:
        data = hdul[0].data.astype(float)

    # Handle multidimensional data (take first 2D plane)
    if data.ndim == 3:
        data = data[0]
    elif data.ndim > 3:
        data = data.reshape(-1, data.shape[-1])[:data.shape[-2], :]

    # Replace NaN/Inf with median
    med = np.nanmedian(data)
    data = np.where(np.isfinite(data), data, med)

    # Smooth the data slightly to avoid hot pixels
    smoothed = ndimage.gaussian_filter(data, sigma=1.5)

    # Find local maxima
    local_max = ndimage.maximum_filter(smoothed, size=15)
    
    # Threshold to only look at very bright sources
    threshold = np.percentile(smoothed, 99.8)
    peaks = (smoothed == local_max) & (smoothed > threshold)
    
    y_idx, x_idx = np.where(peaks)
    
    stars = []
    # Background estimate (median of the whole image since it's a cluster)
    bg_est = med
    
    for y, x in zip(y_idx, x_idx):
        # Exclude edges
        if y < 10 or y >= data.shape[0]-10 or x < 10 or x >= data.shape[1]-10:
            continue
            
        # Simple aperture photometry (7x7 box)
        box = data[y-3:y+4, x-3:x+4]
        flux = np.sum(box) - (bg_est * box.size)
        
        if flux > 0:
            stars.append({
                'x': float(x),
                'y': float(y),
                'flux': float(flux),
                'peak': float(data[y, x])
            })
            
    # Sort by flux descending
    stars.sort(key=lambda s: s['flux'], reverse=True)
    
    # Take top 5
    top_5 = stars[:5]
    
    # Save ground truth
    gt_data = {
        'num_sources_evaluated': len(stars),
        'top_5_stars': top_5,
        'image_shape': data.shape
    }
    
    with open(GT_FILE, 'w') as f:
        json.dump(gt_data, f, indent=2)
        
    print(f"Ground truth computed successfully. Found {len(stars)} bright sources.")
    for i, s in enumerate(top_5):
        print(f"  Rank {i+1}: ({s['x']:.1f}, {s['y']:.1f}) Flux: {s['flux']:.1f}")

except Exception as e:
    print(f"Error computing ground truth: {e}")
PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# Create Macro to load the image immediately in AIJ
MACRO_FILE="/tmp/load_ngc6652.ijm"
cat > "$MACRO_FILE" << 'MACROEOF'
open("/home/ga/AstroImages/ngc6652_project/ngc6652_814w.fits");
run("Enhance Contrast", "saturated=0.35");
MACROEOF
chmod 644 "$MACRO_FILE"
chown ga:ga "$MACRO_FILE"

# Start AstroImageJ with macro
echo "Starting AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 1

# Launch
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' aij -macro '$MACRO_FILE' > /tmp/astroimagej_ga.log 2>&1 &"

# Wait for window
wait_for_window "AstroImageJ\|ImageJ\|ngc6652" 30
sleep 3

# Maximize AIJ
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="