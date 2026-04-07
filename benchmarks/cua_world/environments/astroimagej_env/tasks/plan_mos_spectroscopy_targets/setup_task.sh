#!/bin/bash
set -e

echo "=== Setting up MOS Target Selection Task ==="
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AstroImages/mos_planning"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Ensure the FITS file exists (from pre-installed NGC 6652 samples)
python3 << 'EOF'
import os, glob, subprocess, shutil

src_dir = "/opt/fits_samples/ngc6652"
dest_dir = "/home/ga/AstroImages/mos_planning"

# Locate FITS files, unzip if necessary
fits_files = glob.glob(os.path.join(src_dir, "**/*.fits"), recursive=True) + \
             glob.glob(os.path.join(src_dir, "**/*.fit"), recursive=True)

if not fits_files:
    for z in glob.glob(os.path.join(src_dir, "*.zip")):
        subprocess.run(["unzip", "-o", z, "-d", src_dir], check=False)
    fits_files = glob.glob(os.path.join(src_dir, "**/*.fits"), recursive=True) + \
                 glob.glob(os.path.join(src_dir, "**/*.fit"), recursive=True)

# Select the V-band (555w) image
vband = next((f for f in fits_files if '555' in f.lower()), fits_files[0] if fits_files else None)
if vband:
    dest_path = os.path.join(dest_dir, "ngc6652_555wmos.fits")
    shutil.copy2(vband, dest_path)
    print(f"Copied {vband} to {dest_path}")
else:
    print("ERROR: Could not find required FITS file.")
EOF

chown -R ga:ga "$PROJECT_DIR"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Launch AstroImageJ
launch_astroimagej 120
sleep 2

# Maximize AIJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot as evidence
take_screenshot /tmp/task_start_screenshot.png
echo "=== Task setup complete ==="