#!/bin/bash
set -e
echo "=== Setting up FFT Lamellar Spacing Task ==="

# 1. Create directory structure
su - ga -c "mkdir -p /home/ga/Fiji_Data/raw/eutectic"
su - ga -c "mkdir -p /home/ga/Fiji_Data/results/fft_analysis"

# 2. Prepare Data (AuPbSn40.jpg)
# We use Python to ensure we have a clean TIFF and calculate ground truth
echo "Preparing image and ground truth..."
python3 << 'PYEOF'
import numpy as np
from PIL import Image
from scipy import fft as sp_fft
import os
import urllib.request

# URLs
IMAGE_URL = "https://imagej.net/images/AuPbSn40.jpg"
LOCAL_JPG = "/home/ga/Fiji_Data/raw/eutectic/AuPbSn40.jpg"
LOCAL_TIF = "/home/ga/Fiji_Data/raw/eutectic/AuPbSn40.tif"
GT_DIR = "/var/lib/fiji_ground_truth"
GT_FILE = os.path.join(GT_DIR, "expected_spacing.txt")

# Ensure directories exist
os.makedirs(os.path.dirname(LOCAL_JPG), exist_ok=True)
os.makedirs(GT_DIR, exist_ok=True)

# Download image
try:
    print(f"Downloading {IMAGE_URL}...")
    urllib.request.urlretrieve(IMAGE_URL, LOCAL_JPG)
except Exception as e:
    print(f"Download failed: {e}. Attempting fallback to solid noise.")
    # Fallback: create synthetic lamellar pattern if download fails
    x = np.linspace(0, 40*np.pi, 512)
    y = np.linspace(0, 40*np.pi, 512)
    X, Y = np.meshgrid(x, y)
    Z = np.sin(X + Y) * 127 + 128
    Image.fromarray(Z.astype(np.uint8)).save(LOCAL_JPG)

# Convert to TIFF for the agent
img_pil = Image.open(LOCAL_JPG).convert('L')
img_pil.save(LOCAL_TIF)
print(f"Saved TIFF to {LOCAL_TIF}")

# --- Calculate Ground Truth Spacing ---
# The task asks for lamellar spacing. In FFT, this corresponds to the dominant spatial frequency.
img_array = np.array(img_pil).astype(float)

# Compute 2D FFT
f = sp_fft.fft2(img_array)
fshift = sp_fft.fftshift(f)
magnitude_spectrum = 20 * np.log(np.abs(fshift) + 1)
power = np.abs(fshift)**2

# Compute radial profile to find dominant frequency ring
h, w = power.shape
cy, cx = h // 2, w // 2
y, x = np.ogrid[-cy:h-cy, -cx:w-cx]
r = np.sqrt(x**2 + y**2).astype(int)

# Bin by radius
tbin = np.bincount(r.ravel(), power.ravel())
nr = np.bincount(r.ravel())
radial_profile = tbin / np.maximum(nr, 1)

# Find peak in relevant range (skip DC component at 0 and very low freqs)
# Eutectic lamellae are usually mid-frequency
start_idx = 5 
# Limit search to half dimension
end_idx = min(h, w) // 2 
peak_r_idx = start_idx + np.argmax(radial_profile[start_idx:end_idx])

# Convert to spatial units
# Spatial Period (pixels) = Image_Width / Frequency_Radius
# Note: Since FFT is symmetric and we use full width, the fundamental freq resolution is 1/Width.
# The frequency at radius r is r cycles per Width.
# So Period = Width / r
spatial_period_px = w / peak_r_idx

# Calibration: 0.49 um/pixel
calibrated_spacing_um = spatial_period_px * 0.49

print(f"Ground Truth Calculation:")
print(f"  Peak Frequency Radius: {peak_r_idx} pixels")
print(f"  Spatial Period: {spatial_period_px:.2f} pixels")
print(f"  Calibrated Spacing: {calibrated_spacing_um:.2f} um")

with open(GT_FILE, "w") as f:
    f.write(f"{calibrated_spacing_um:.4f}")

# Set permissions
os.chmod(LOCAL_TIF, 0o666)
PYEOF

# Fix ownership
chown -R ga:ga /home/ga/Fiji_Data

# 3. Create Calibration Info Text
cat > /home/ga/Fiji_Data/raw/eutectic/calibration_info.txt << EOF
Image: AuPbSn40.tif
Pixel Size: 0.49 micrometer
Unit: um
EOF
chown ga:ga /home/ga/Fiji_Data/raw/eutectic/calibration_info.txt

# 4. Record start time
date +%s > /tmp/task_start_time.txt

# 5. Launch Fiji with the image
echo "Launching Fiji..."
pkill -f "fiji" || true
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh /home/ga/Fiji_Data/raw/eutectic/AuPbSn40.tif" &

# Wait for Fiji window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize
sleep 2
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "AuPbSn40.tif" 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="