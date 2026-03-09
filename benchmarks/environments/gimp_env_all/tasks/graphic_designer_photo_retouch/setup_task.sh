#!/bin/bash
set -e

echo "=== Setting up graphic_designer_photo_retouch task ==="

# Record task start timestamp
date +%s > /tmp/photo_retouch_task_start

# Ensure Python image tools available
apt-get install -y -qq python3-pil python3-numpy 2>/dev/null || pip3 install Pillow numpy 2>/dev/null || true

echo "Downloading portrait photograph..."
cd /home/ga/Desktop/

# Download a real portrait photograph
# Primary: Abraham Lincoln portrait from Wikimedia (public domain, historically important)
wget -q --timeout=30 -O portrait_photo.jpg \
  "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Abraham_Lincoln_O-77_matte_collodion_print.jpg/800px-Abraham_Lincoln_O-77_matte_collodion_print.jpg" 2>/dev/null

# Validate download (>30KB)
if [ ! -f portrait_photo.jpg ] || [ $(stat -c%s portrait_photo.jpg 2>/dev/null || echo 0) -lt 30000 ]; then
  echo "Primary source failed, trying fallback..."
  # Fallback: Thomas Edison portrait (public domain)
  wget -q --timeout=30 -O portrait_photo.jpg \
    "https://upload.wikimedia.org/wikipedia/commons/thumb/9/9d/Thomas_Edison2.jpg/800px-Thomas_Edison2.jpg" 2>/dev/null
fi

# Second fallback
if [ ! -f portrait_photo.jpg ] || [ $(stat -c%s portrait_photo.jpg 2>/dev/null || echo 0) -lt 30000 ]; then
  echo "Second fallback..."
  wget -q --timeout=30 -O portrait_photo.jpg \
    "https://upload.wikimedia.org/wikipedia/commons/thumb/3/33/Albert_Einstein_Head.jpg/800px-Albert_Einstein_Head.jpg" 2>/dev/null
fi

# Third fallback: any real portrait from Unsplash
if [ ! -f portrait_photo.jpg ] || [ $(stat -c%s portrait_photo.jpg 2>/dev/null || echo 0) -lt 30000 ]; then
  echo "Third fallback..."
  wget -q --timeout=30 -O portrait_photo.jpg \
    "https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=800&q=70" 2>/dev/null
fi

# Final check
if [ ! -f portrait_photo.jpg ] || [ $(stat -c%s portrait_photo.jpg 2>/dev/null || echo 0) -lt 20000 ]; then
  echo "ERROR: Failed to download portrait_photo.jpg from all sources. Cannot proceed."
  exit 1
fi

# Set permissions
chown ga:ga /home/ga/Desktop/portrait_photo.jpg
chmod 644 /home/ga/Desktop/portrait_photo.jpg

# Save baseline copy and compute pixel statistics for verifier
cp /home/ga/Desktop/portrait_photo.jpg /tmp/portrait_photo_baseline.jpg

python3 -c "
from PIL import Image
import json
import numpy as np
img = Image.open('/home/ga/Desktop/portrait_photo.jpg').convert('RGB')
arr = np.array(img)
r = arr[:,:,0].astype(float)
g = arr[:,:,1].astype(float)
b = arr[:,:,2].astype(float)
# Compute baseline statistics
gt = {
    'width': img.size[0],
    'height': img.size[1],
    'r_mean': float(np.mean(r)),
    'g_mean': float(np.mean(g)),
    'b_mean': float(np.mean(b)),
    'brightness_mean': float(np.mean(arr)),
    'brightness_p5': float(np.percentile(arr, 5)),
    'brightness_p95': float(np.percentile(arr, 95)),
    'contrast_range': float(np.percentile(arr, 95) - np.percentile(arr, 5)),
}
with open('/tmp/photo_retouch_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f'Portrait: {img.size[0]}x{img.size[1]}, contrast_range={gt[\"contrast_range\"]:.1f}')
print(f'Channel means: R={gt[\"r_mean\"]:.0f} G={gt[\"g_mean\"]:.0f} B={gt[\"b_mean\"]:.0f}')
" 2>/dev/null || true

echo "Opening GIMP with portrait photograph..."
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/portrait_photo.jpg > /tmp/gimp_photo_retouch.log 2>&1 &"
sleep 5

echo "=== Setup complete ==="
echo "  portrait_photo.jpg is on the Desktop and open in GIMP"
