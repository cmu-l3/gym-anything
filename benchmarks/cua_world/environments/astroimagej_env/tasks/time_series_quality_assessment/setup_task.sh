#!/bin/bash
echo "=== Setting up Time-Series Quality Assessment Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create working directories
PROJECT_DIR="/home/ga/AstroImages/wasp12b_qc"
RAW_DIR="$PROJECT_DIR/raw"
rm -rf "$PROJECT_DIR"
mkdir -p "$RAW_DIR"

# Extract WASP-12b data
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$WASP12_CACHE" ]; then
    echo "ERROR: Cached WASP-12b data not found at $WASP12_CACHE!"
    exit 1
fi

echo "Extracting WASP-12b frames to $RAW_DIR..."
tar -xzf "$WASP12_CACHE" -C /tmp/ 2>/dev/null
mv /tmp/WASP-12b/*.fits "$RAW_DIR/" 2>/dev/null || true
rm -rf /tmp/WASP-12b

# Verify extraction
FITS_COUNT=$(ls -1 "$RAW_DIR"/*.fits 2>/dev/null | wc -l)
echo "Extracted $FITS_COUNT FITS files."

# Set permissions
chown -R ga:ga /home/ga/AstroImages

# Compute Ground Truth dynamically based on the actual image data
echo "Computing ground truth for Sky Background and Seeing (FWHM)..."
python3 << 'PYEOF'
import glob, json
import numpy as np
from astropy.io import fits

files = sorted(glob.glob('/home/ga/AstroImages/wasp12b_qc/raw/*.fits'))
results = []
for i, f in enumerate(files):
    try:
        data = fits.getdata(f)
        bg = np.median(data)
        
        # FWHM proxy: standard deviation of the top 0.5% pixels.
        # When seeing is bad (high FWHM), stars smear out, lowering the peak 
        # intensity and causing the top pixels to have lower variance.
        top_pixels = data[data > np.percentile(data, 99.5)]
        seeing_proxy = np.std(top_pixels) if len(top_pixels) > 0 else 0
        
        results.append({
            'frame': i + 1, 
            'bg': float(bg), 
            'seeing_proxy': float(seeing_proxy)
        })
    except Exception as e:
        print(f"Error processing {f}: {e}")

# Worst Sky Background = Highest Background (median)
results.sort(key=lambda x: x['bg'], reverse=True)
worst_bg = [x['frame'] for x in results[:15]]

# Worst Seeing = Widest FWHM = Lowest top-pixel variance (most smeared)
results.sort(key=lambda x: x['seeing_proxy'], reverse=False)
worst_fwhm = [x['frame'] for x in results[:15]]

gt_data = {
    'worst_bg': worst_bg,
    'worst_fwhm': worst_fwhm,
    'total_frames_analyzed': len(results)
}

with open('/tmp/qc_ground_truth.json', 'w') as out:
    json.dump(gt_data, out, indent=2)

print(f"Ground truth calculated. Worst BG frames: {worst_bg[:5]}...")
print(f"Worst Seeing frames: {worst_fwhm[:5]}...")
PYEOF

chmod 644 /tmp/qc_ground_truth.json

# Launch AstroImageJ empty (agent must load the image sequence)
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

AIJ_PATH=""
for path in "/usr/local/bin/aij" "/opt/astroimagej/astroimagej/bin/AstroImageJ" "/opt/astroimagej/AstroImageJ/bin/AstroImageJ"; do
    if [ -x "$path" ]; then
        AIJ_PATH="$path"
        break
    fi
done

if [ -n "$AIJ_PATH" ]; then
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$AIJ_PATH' > /tmp/astroimagej_ga.log 2>&1" &
    sleep 5
    
    # Wait for window and maximize
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ"; then
            DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
            DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || true
            break
        fi
        sleep 1
    done
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="