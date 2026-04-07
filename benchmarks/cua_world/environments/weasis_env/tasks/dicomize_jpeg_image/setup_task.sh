#!/bin/bash
echo "=== Setting up dicomize_jpeg_image task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Directories
DESKTOP_DIR="/home/ga/Desktop"
EXPORT_DIR="/home/ga/DICOM/exports"

mkdir -p "$DESKTOP_DIR"
mkdir -p "$EXPORT_DIR"

# Clean up any existing exports to ensure a clean state
rm -f "$EXPORT_DIR"/*.dcm 2>/dev/null || true

# Download a realistic clinical image (Wikipedia Commons - Normal Gastric Mucosa)
IMG_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/d/d7/Normal_gastric_mucosa.jpg/800px-Normal_gastric_mucosa.jpg"
IMG_PATH="$DESKTOP_DIR/endoscopy_capture.jpg"

echo "Downloading source JPEG..."
curl -sL "$IMG_URL" -o "$IMG_PATH"

# Fallback: Create a synthetic endoscopy-like image if download fails
if [ ! -f "$IMG_PATH" ] || [ ! -s "$IMG_PATH" ]; then
    echo "Download failed. Generating synthetic clinical image..."
    python3 << 'PYEOF'
import numpy as np
from PIL import Image
import cv2

size = 800
img = np.zeros((size, size, 3), dtype=np.uint8)
# Base pinkish-red tissue color
img[:, :] = [160, 60, 80]

# Add noise for texture
noise = np.random.normal(0, 15, (size, size, 3)).astype(np.int16)
img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)

# Add some darker pseudo-structures (vessels/folds)
for _ in range(8):
    x, y = np.random.randint(200, 600, 2)
    cv2.circle(img, (x, y), np.random.randint(30, 100), (100, 30, 40), -1)

# Apply gaussian blur to smooth structures
img = cv2.GaussianBlur(img, (45, 45), 0)

# Apply a circular vignette/mask (typical of endoscopy)
mask = np.zeros((size, size), dtype=np.uint8)
cv2.circle(mask, (size//2, size//2), 360, 255, -1)
img[mask == 0] = [0, 0, 0]

Image.fromarray(img).save("/home/ga/Desktop/endoscopy_capture.jpg", quality=95)
PYEOF
fi

chown ga:ga "$IMG_PATH"
chmod 644 "$IMG_PATH"
chown -R ga:ga "$EXPORT_DIR"

# Make sure Weasis is not running
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis (Empty State)
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis to load
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "weasis"; then
        break
    fi
    sleep 2
done

# Dismiss first-run dialog if it appears
sleep 3
if type dismiss_first_run_dialog &>/dev/null; then
    dismiss_first_run_dialog
else
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
fi

# Maximize Weasis
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="