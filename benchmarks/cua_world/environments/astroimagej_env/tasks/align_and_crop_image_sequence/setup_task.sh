#!/bin/bash
echo "=== Setting up Align and Crop Image Sequence Task ==="

source /workspace/scripts/task_utils.sh

# Directories
RAW_DIR="/home/ga/AstroImages/raw_sequence"
OUT_DIR="/home/ga/AstroImages/aligned_sequence"

rm -rf "$RAW_DIR" "$OUT_DIR"
mkdir -p "$RAW_DIR" "$OUT_DIR"

# ============================================================
# Prepare Drifting Sequence from Real Data
# Extract 20 frames from WASP-12b and artificially add drift
# ============================================================
echo "Preparing drifting image sequence..."

python3 << 'PYEOF'
import os
import glob
import tarfile
import shutil
import numpy as np
from astropy.io import fits

WASP12_CACHE = "/opt/fits_samples/WASP-12b_calibrated.tar.gz"
RAW_DIR = "/home/ga/AstroImages/raw_sequence"

if not os.path.exists(WASP12_CACHE):
    print(f"ERROR: Cached data not found at {WASP12_CACHE}")
    exit(1)

# Extract first 20 FITS files to a temporary directory
TMP_EXTRACT = "/tmp/wasp_extract"
os.makedirs(TMP_EXTRACT, exist_ok=True)

print("Extracting frames from archive...")
with tarfile.open(WASP12_CACHE, 'r:gz') as tar:
    members = [m for m in tar.getmembers() if m.name.endswith('.fits')]
    members = sorted(members, key=lambda x: x.name)[:20]
    tar.extractall(path=TMP_EXTRACT, members=members)

extracted_files = sorted(glob.glob(f"{TMP_EXTRACT}/**/*.fits", recursive=True))

print(f"Injecting severe tracking drift into {len(extracted_files)} frames...")
for i, fpath in enumerate(extracted_files):
    # Read data
    with fits.open(fpath) as hdul:
        data = hdul[0].data
        hdr = hdul[0].header
        
        # Inject artificial drift (dx = 3px/frame, dy = 2px/frame)
        dy, dx = i * 2, i * 3
        
        shifted = np.zeros_like(data)
        if dy > 0 and dx > 0:
            shifted[dy:, dx:] = data[:-dy, :-dx]
        else:
            shifted = data.copy()
            
        # Write to raw_sequence directory
        out_name = f"drifting_frame_{i:02d}.fits"
        out_path = os.path.join(RAW_DIR, out_name)
        fits.writeto(out_path, shifted, hdr, overwrite=True)

# Cleanup temp
shutil.rmtree(TMP_EXTRACT)
print("Drifting sequence prepared successfully.")
PYEOF

# Ensure permissions are correct for the agent
chown -R ga:ga /home/ga/AstroImages

# ============================================================
# Record starting state
# ============================================================
date +%s > /tmp/task_start_timestamp

# ============================================================
# Launch AstroImageJ
# ============================================================
echo "Launching AstroImageJ..."

pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' /usr/local/bin/aij > /tmp/astroimagej_ga.log 2>&1" &

# Wait for AstroImageJ to start
sleep 8
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|AstroImageJ"; then
        echo "AstroImageJ window detected"
        break
    fi
    sleep 1
done

# Maximize AIJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="