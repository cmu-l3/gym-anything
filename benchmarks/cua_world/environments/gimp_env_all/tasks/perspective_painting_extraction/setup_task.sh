#!/bin/bash
set -e

echo "=== Setting up perspective_painting_extraction task ==="

# Ensure Python image tools available
apt-get install -y -qq python3-pil python3-numpy 2>/dev/null || pip3 install Pillow numpy 2>/dev/null || true

# Delete stale output files BEFORE recording timestamp
rm -f /home/ga/Desktop/painting_corrected.png 2>/dev/null || true
rm -f /home/ga/Desktop/painting_corrected.PNG 2>/dev/null || true
rm -f /home/ga/Documents/painting_corrected.png 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/perspective_painting_task_start

echo "Downloading painting for gallery photograph..."
cd /tmp/
rm -f source_painting_raw.jpg 2>/dev/null || true

# Download a real painting (full-res URLs — thumbnail URLs are rate-limited)
# Primary: Vermeer's Girl with a Pearl Earring (public domain, ~6MB, resized in Python)
wget -q --timeout=30 -O source_painting_raw.jpg \
  "https://upload.wikimedia.org/wikipedia/commons/d/d7/Meisje_met_de_parel.jpg" 2>/dev/null || true

# Validate download (>10KB)
if [ ! -f source_painting_raw.jpg ] || [ $(stat -c%s source_painting_raw.jpg 2>/dev/null || echo 0) -lt 10000 ]; then
  echo "Primary source failed, trying fallback..."
  rm -f source_painting_raw.jpg 2>/dev/null || true
  # Fallback: Mona Lisa (full resolution)
  wget -q --timeout=30 -O source_painting_raw.jpg \
    "https://upload.wikimedia.org/wikipedia/commons/e/ec/Mona_Lisa%2C_by_Leonardo_da_Vinci%2C_from_C2RMF_retouched.jpg" 2>/dev/null || true
fi

# Second fallback: Renoir painting (full resolution)
if [ ! -f source_painting_raw.jpg ] || [ $(stat -c%s source_painting_raw.jpg 2>/dev/null || echo 0) -lt 10000 ]; then
  echo "Second fallback..."
  rm -f source_painting_raw.jpg 2>/dev/null || true
  wget -q --timeout=30 -O source_painting_raw.jpg \
    "https://upload.wikimedia.org/wikipedia/commons/8/8d/Pierre-Auguste_Renoir_-_Luncheon_of_the_Boating_Party_-_Google_Art_Project.jpg" 2>/dev/null || true
fi

echo "Generating gallery photograph with perspective distortion and color cast..."

python3 << 'PYEOF'
import sys
import os
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

np.random.seed(42)

# --- Step 1: Load painting or generate synthetic ---
pw, ph = 800, 600
painting = None

try:
    raw_path = '/tmp/source_painting_raw.jpg'
    if os.path.exists(raw_path) and os.path.getsize(raw_path) > 10000:
        painting = Image.open(raw_path).convert('RGB')
        painting = painting.resize((pw, ph), Image.LANCZOS)
        print(f"Loaded real painting: {painting.size}")
except Exception as e:
    print(f"Could not load painting: {e}")
    painting = None

if painting is None:
    print("Generating synthetic painting (all downloads failed)...")
    arr = np.zeros((ph, pw, 3), dtype=np.uint8)
    sky_h = int(ph * 0.4)
    for y in range(sky_h):
        r = y / sky_h
        arr[y, :] = [int(40 + 80*r), int(80 + 100*r), int(180 + 50*r)]
    for y in range(sky_h, ph):
        r = (y - sky_h) / (ph - sky_h)
        base = np.array([int(70 + 60*r), int(130 - 50*r), int(50 + 20*r)])
        noise = np.random.randint(-10, 10, (pw, 3))
        arr[y, :] = np.clip(base + noise, 0, 255)
    painting = Image.fromarray(arr)
    draw = ImageDraw.Draw(painting)
    draw.rectangle([300, 80, 500, 250], fill=(120, 100, 85))
    for wy in range(100, 240, 30):
        for wx in range(320, 490, 40):
            draw.rectangle([wx, wy, wx+20, wy+18], fill=(210, 200, 140))
    draw.ellipse([580, 100, 720, 240], fill=(45, 95, 40))
    draw.rectangle([640, 240, 660, 310], fill=(90, 65, 40))
    draw.ellipse([100, 120, 200, 200], fill=(220, 220, 230))
    draw.ellipse([140, 130, 260, 190], fill=(225, 225, 235))

# Save ground truth painting (what the corrected output should approximate)
painting.save('/tmp/painting_ground_truth.png')

# --- Step 2: Add gold frame around painting ---
frame_w = 14
fw = pw + 2 * frame_w
fh = ph + 2 * frame_w

# Create frame with subtle inner/outer coloring
framed = Image.new('RGBA', (fw, fh), (175, 150, 75, 255))
inner_frame = Image.new('RGBA', (pw + 6, ph + 6), (155, 135, 65, 255))
framed.paste(inner_frame, (frame_w - 3, frame_w - 3))
framed.paste(painting.convert('RGBA'), (frame_w, frame_w))

# --- Step 3: Apply perspective transform (simulate camera at angle) ---
def find_coeffs(source_coords, target_coords):
    """Compute perspective transform coefficients.
    For PIL: maps output coords (source_coords) to input coords (target_coords).
    """
    matrix = []
    for (sx, sy), (tx, ty) in zip(source_coords, target_coords):
        matrix.append([tx, ty, 1, 0, 0, 0, -sx*tx, -sx*ty])
        matrix.append([0, 0, 0, tx, ty, 1, -sy*tx, -sy*ty])
    A = np.array(matrix, dtype=float)
    B = np.array([c for p in source_coords for c in p], dtype=float)
    return np.linalg.solve(A, B).tolist()

# Original rectangle corners of the framed painting
src_rect = [(0, 0), (fw, 0), (fw, fh), (0, fh)]

# Destination trapezoid: photographed from the right side
# Left side is farther from camera (appears shorter/narrower)
# Right side is closer (appears near original size)
dst_trap = [
    (100, 60),             # top-left: pushed significantly right and down
    (fw - 8, 12),          # top-right: near original
    (fw - 12, fh - 15),    # bottom-right: near original
    (80, fh - 70),         # bottom-left: pushed significantly right and up
]

coeffs = find_coeffs(src_rect, dst_trap)
warped = framed.transform(
    (fw, fh), Image.PERSPECTIVE, coeffs, Image.BICUBIC,
    fillcolor=(0, 0, 0, 0)
)

# --- Step 4: Create gallery wall and composite ---
wall_w, wall_h = 1300, 950
wall_color = (195, 185, 170)
wall = Image.new('RGBA', (wall_w, wall_h), (*wall_color, 255))

# Add subtle wall texture using a fixed random state
rng_wall = np.random.RandomState(123)
wall_arr = np.array(wall)
wall_noise = rng_wall.randint(-5, 5, (wall_h, wall_w, 3), dtype=np.int16)
wall_arr[:,:,:3] = np.clip(
    wall_arr[:,:,:3].astype(np.int16) + wall_noise, 0, 255
).astype(np.uint8)
wall = Image.fromarray(wall_arr)

# Add a subtle shadow beneath the painting for realism
shadow_draw = ImageDraw.Draw(wall)
ox = (wall_w - fw) // 2
oy = (wall_h - fh) // 2 - 30
shadow_draw.rectangle(
    [ox + 8, oy + 8, ox + fw + 8, oy + fh + 8],
    fill=(160, 155, 145, 180)
)

# Paste warped painting+frame onto wall
wall.paste(warped, (ox, oy), warped)
gallery = wall.convert('RGB')

# --- Step 5: Apply warm color cast (gallery incandescent lighting) ---
g_arr = np.array(gallery).astype(np.int16)
g_arr[:,:,0] = np.clip(g_arr[:,:,0] + 15, 0, 255)   # boost red
g_arr[:,:,1] = np.clip(g_arr[:,:,1] + 5, 0, 255)    # slight green
g_arr[:,:,2] = np.clip(g_arr[:,:,2] - 20, 0, 255)   # reduce blue (warm cast)
gallery = Image.fromarray(g_arr.astype(np.uint8))

# --- Step 6: Slight softness (camera lens) ---
gallery = gallery.filter(ImageFilter.GaussianBlur(radius=0.5))

# --- Save final gallery photo ---
gallery.save('/home/ga/Desktop/gallery_photo.jpg', quality=90)

# --- Step 7: Save ground truth metadata for verifier ---
final_arr = np.array(gallery)
ch_means = [float(np.mean(final_arr[:,:,c])) for c in range(3)]

gt = {
    'painting_width': pw,
    'painting_height': ph,
    'painting_aspect_ratio': round(pw / ph, 4),
    'frame_width': frame_w,
    'wall_size': [wall_w, wall_h],
    'painting_offset': [ox, oy],
    'color_cast': {'red_shift': 15, 'green_shift': 5, 'blue_shift': -20},
    'expected_output_width': 1200,
    'expected_output_height': round(1200 * ph / pw),
    'source_channel_means': ch_means,
    'source_channel_std': float(np.std(ch_means)),
}

with open('/tmp/perspective_painting_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

# Save baseline copy
gallery.save('/tmp/gallery_photo_baseline.jpg', quality=95)

print(f"Gallery photo created: {gallery.size[0]}x{gallery.size[1]}")
print(f"Painting: {pw}x{ph}, frame: {frame_w}px")
print(f"Channel means: R={ch_means[0]:.0f} G={ch_means[1]:.0f} B={ch_means[2]:.0f}")
print(f"Channel std (color cast indicator): {gt['source_channel_std']:.2f}")
PYEOF

# Set ownership and permissions
chown ga:ga /home/ga/Desktop/gallery_photo.jpg
chmod 644 /home/ga/Desktop/gallery_photo.jpg

echo "Opening GIMP with gallery photograph..."
su - ga -c "DISPLAY=:1 gimp /home/ga/Desktop/gallery_photo.jpg > /tmp/gimp_perspective_task.log 2>&1 &"
sleep 5

echo "=== Setup complete ==="
echo "  gallery_photo.jpg is on the Desktop and open in GIMP"
