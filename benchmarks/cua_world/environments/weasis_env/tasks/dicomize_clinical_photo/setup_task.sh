#!/bin/bash
echo "=== Setting up dicomize_clinical_photo task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
DESKTOP_DIR="/home/ga/Desktop"
EXPORT_DIR="/home/ga/DICOM/exports"
PHOTO_PATH="$DESKTOP_DIR/clinical_photo.jpg"

mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Clean up any existing exported DICOM files to ensure a fresh state
rm -f "$EXPORT_DIR"/*.dcm 2>/dev/null || true
rm -f "$EXPORT_DIR"/*.DCM 2>/dev/null || true

# Download a real clinical photograph (Melanoma) from Wikimedia Commons
echo "Fetching clinical photograph..."
wget -q -O "$PHOTO_PATH" "https://upload.wikimedia.org/wikipedia/commons/4/4d/Melanoma.jpg"

# Fallback: Generate an image using Python if wget fails (e.g. no internet)
if [ ! -s "$PHOTO_PATH" ]; then
    echo "Wget failed. Generating synthetic clinical photo fallback..."
    python3 << 'PYEOF'
try:
    from PIL import Image, ImageDraw
    img = Image.new('RGB', (1024, 768), color=(255, 218, 185))
    d = ImageDraw.Draw(img)
    # Draw a simulated skin lesion
    d.ellipse([400, 300, 600, 480], fill=(80, 30, 30))
    d.ellipse([420, 320, 580, 460], fill=(50, 20, 20))
    # Add some texture/noise
    import random
    for _ in range(2000):
        x, y = random.randint(350, 650), random.randint(250, 530)
        d.point((x, y), fill=(40, 10, 10))
    img.save('/home/ga/Desktop/clinical_photo.jpg', quality=95)
except Exception as e:
    print(f"Failed to create fallback image: {e}")
PYEOF
fi

chown ga:ga "$PHOTO_PATH"
chmod 644 "$PHOTO_PATH"

# Ensure Weasis is stopped before starting fresh
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis without a pre-loaded DICOM file (agent must import)
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"
sleep 8

# Wait for Weasis UI to appear
wait_for_weasis 60

# Maximize Weasis Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Clinical photo ready at: $PHOTO_PATH"