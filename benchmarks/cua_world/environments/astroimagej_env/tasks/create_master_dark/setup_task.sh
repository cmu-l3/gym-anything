#!/bin/bash
set -e
echo "=== Setting up Create Master Dark task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
su - ga -c "mkdir -p /home/ga/AstroImages/raw/darks"
su - ga -c "mkdir -p /home/ga/AstroImages/processed"
su - ga -c "rm -f /home/ga/AstroImages/processed/master_dark.fits 2>/dev/null"

# Prepare 5 real dark frames robustly
echo "Preparing real dark frames..."
cat > /tmp/prepare_darks.py << 'EOF'
import os
import shutil
import urllib.request
from astropy.io import fits

target_dir = "/home/ga/AstroImages/raw/darks"
darks_found = []

# Attempt 1: Look through the locally cached Palomar LFC datasets from env install
search_dir = "/opt/fits_samples/palomar_lfc"
if os.path.exists(search_dir):
    for root, dirs, files in os.walk(search_dir):
        for f in files:
            if f.endswith('.fits'):
                path = os.path.join(root, f)
                try:
                    # Check header or filename for dark indicators
                    if 'dark' in f.lower() or 'dark' in str(fits.getheader(path).get('IMAGETYP', '')).lower():
                        darks_found.append(path)
                except Exception:
                    pass

# Attempt 2: Fallback to downloading real dark frames from Astropy CCD Reduction Tutorial
if len(darks_found) < 5:
    print("Local darks insufficient. Downloading real calibration frames from Astropy...")
    urls = [
        "https://raw.githubusercontent.com/astropy/astropy-data/gh-pages/tutorials/ccd-reduction/dark_10.fits",
        "https://raw.githubusercontent.com/astropy/astropy-data/gh-pages/tutorials/ccd-reduction/dark_11.fits",
        "https://raw.githubusercontent.com/astropy/astropy-data/gh-pages/tutorials/ccd-reduction/dark_12.fits",
        "https://raw.githubusercontent.com/astropy/astropy-data/gh-pages/tutorials/ccd-reduction/dark_13.fits",
        "https://raw.githubusercontent.com/astropy/astropy-data/gh-pages/tutorials/ccd-reduction/dark_14.fits"
    ]
    for i, url in enumerate(urls):
        dest = os.path.join(target_dir, f"dark_{i+1}.fits")
        try:
            urllib.request.urlretrieve(url, dest)
            darks_found.append(dest)
        except Exception as e:
            print(f"Failed to download {url}: {e}")

# Copy exactly 5 to target directory
for i in range(min(5, len(darks_found))):
    shutil.copy(darks_found[i], os.path.join(target_dir, f"dark_{i+1}.fits"))
EOF

python3 /tmp/prepare_darks.py
chown -R ga:ga /home/ga/AstroImages/raw/darks

# Ensure AstroImageJ is running
if ! pgrep -f "AstroImageJ\|aij" > /dev/null; then
    echo "Starting AstroImageJ..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/aij &"
    
    # Wait for window to appear
    for i in {1..20}; do
        if DISPLAY=:1 wmctrl -l | grep -i "ImageJ"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus AstroImageJ
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || true

# Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="