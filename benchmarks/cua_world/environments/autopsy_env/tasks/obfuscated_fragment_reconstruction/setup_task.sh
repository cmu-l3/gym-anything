#!/bin/bash
# Setup script for obfuscated_fragment_reconstruction task
echo "=== Setting up obfuscated_fragment_reconstruction task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Clean up stale artifacts ────────────────────────────────────────────────
rm -f /tmp/obfuscated_fragment_result.json /tmp/obfuscated_fragment_start_time \
      /tmp/source_image.jpg /tmp/part_a /tmp/part_b /tmp/part_c 2>/dev/null || true

for d in /home/ga/Cases/Fragment_Recovery_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports/fragments
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

mkdir -p /var/lib/app/ground_truth
chmod 700 /var/lib/app/ground_truth

# ── 2. Obtain or Generate Real JPEG Image ─────────────────────────────────────
echo "Acquiring realistic JPEG evidence..."
wget -q --timeout=15 -O /tmp/source_image.jpg \
    "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Flower_poster_2.jpg/800px-Flower_poster_2.jpg" 2>/dev/null || true

# If download failed or returned HTML error, generate a complex procedural JPEG
if [ ! -s /tmp/source_image.jpg ] || head -c 100 /tmp/source_image.jpg | grep -qi "html"; then
    echo "Download failed, generating procedural JPEG..."
    python3 << 'PYEOF'
import random
try:
    from PIL import Image, ImageDraw
    img = Image.new('RGB', (1024, 768), color=(20, 30, 40))
    d = ImageDraw.Draw(img)
    for _ in range(800):
        x0 = random.randint(0, 1024)
        y0 = random.randint(0, 768)
        x1 = x0 + random.randint(10, 150)
        y1 = y0 + random.randint(10, 150)
        d.ellipse([x0, y0, x1, y1], fill=(random.randint(50,255), random.randint(50,255), random.randint(50,255)))
    img.save('/tmp/source_image.jpg', 'JPEG', quality=95)
except Exception as e:
    print(f"PIL fallback failed: {e}")
PYEOF
fi

if [ ! -s /tmp/source_image.jpg ]; then
    echo "FATAL: Could not acquire or generate source image"
    exit 1
fi

# ── 3. Hash the original and split it ─────────────────────────────────────────
md5sum /tmp/source_image.jpg | awk '{print $1}' > /var/lib/app/ground_truth/original_hash.txt
echo "Ground truth hash saved: $(cat /var/lib/app/ground_truth/original_hash.txt)"

python3 << 'PYEOF'
import os
try:
    with open('/tmp/source_image.jpg', 'rb') as f:
        data = f.read()
    p1 = len(data) // 3
    p2 = 2 * len(data) // 3
    with open('/tmp/part_a', 'wb') as f: f.write(data[:p1])
    with open('/tmp/part_b', 'wb') as f: f.write(data[p1:p2])
    with open('/tmp/part_c', 'wb') as f: f.write(data[p2:])
except Exception as e:
    print(f"Error splitting file: {e}")
PYEOF

# ── 4. Create FAT32 Evidence Disk Image ───────────────────────────────────────
echo "Creating FAT32 forensic image..."
IMAGE="/home/ga/evidence/exfil_usb.dd"
mkdir -p /home/ga/evidence

dd if=/dev/zero of="$IMAGE" bs=1M count=12 2>/dev/null
mkfs.vfat -F 32 -n "EXFIL_USB" "$IMAGE" >/dev/null 2>&1

# Mount and populate
mkdir -p /tmp/fat_mnt
mount -o loop "$IMAGE" /tmp/fat_mnt

mkdir -p /tmp/fat_mnt/System/Cache
mkdir -p /tmp/fat_mnt/Temp/Windows
mkdir -p /tmp/fat_mnt/Recycled

# Add noise files
echo "OS cache index data" > /tmp/fat_mnt/System/Cache/thumbs.db
echo "Temporary installation logs for Windows Update" > /tmp/fat_mnt/Temp/Windows/install.log
echo "Deleted registry keys backup" > /tmp/fat_mnt/Recycled/INFO2
date > /tmp/fat_mnt/volume_id.txt

# Place the fragments
# part_a (JPEG Header) -> swap_frag.sys
# part_b (Middle)      -> sys_cache.bin
# part_c (JPEG Footer) -> win_temp.dat
cp /tmp/part_a /tmp/fat_mnt/Recycled/swap_frag.sys
cp /tmp/part_b /tmp/fat_mnt/System/Cache/sys_cache.bin
cp /tmp/part_c /tmp/fat_mnt/Temp/Windows/win_temp.dat

sync
umount /tmp/fat_mnt

# Remount to delete (ensuring proper E5 deletion markers in FAT32)
mount -o loop "$IMAGE" /tmp/fat_mnt
rm -f /tmp/fat_mnt/Recycled/swap_frag.sys
rm -f /tmp/fat_mnt/System/Cache/sys_cache.bin
rm -f /tmp/fat_mnt/Temp/Windows/win_temp.dat
sync
umount /tmp/fat_mnt

chown ga:ga "$IMAGE"
chmod 644 "$IMAGE"
echo "Evidence image prepared: $IMAGE"

# ── 5. Setup Application State ────────────────────────────────────────────────
date +%s > /tmp/obfuscated_fragment_start_time

kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

# Wait until Welcome screen is visible, clear dialogs
WELCOME_ELAPSED=0
while [ $WELCOME_ELAPSED -lt 300 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Autopsy window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "autopsy" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="