#!/bin/bash
set -e
echo "=== Setting up Particle Inclusion Analysis Task ==="

# 1. Define paths and users
USER_GA="ga"
HOME_DIR="/home/$USER_GA"
DATA_DIR="$HOME_DIR/Fiji_Data/raw/particles"
RESULTS_DIR="$HOME_DIR/Fiji_Data/results/particles"

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Create directories with correct permissions
mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
chown -R $USER_GA:$USER_GA "$HOME_DIR/Fiji_Data"

# 4. Clear previous results (CRITICAL for valid testing)
rm -f "$RESULTS_DIR"/* 2>/dev/null || true

# 5. Prepare Data: Download and Convert Image
# We use the standard 'particles.gif' from ImageJ samples but rename it to look like a micrograph
SOURCE_URL="https://imagej.nih.gov/ij/images/particles.gif"
TARGET_FILE="$DATA_DIR/specimen_micrograph.tif"

echo "Downloading sample image..."
if [ ! -f "$TARGET_FILE" ]; then
    # Try primary source
    wget -q --timeout=30 "$SOURCE_URL" -O /tmp/temp_particles.gif || \
    # Fallback mirror
    wget -q --timeout=30 "https://wsr.imagej.net/images/particles.gif" -O /tmp/temp_particles.gif

    if [ -f /tmp/temp_particles.gif ]; then
        # Convert GIF to TIFF using ImageMagick (convert is available in env)
        # Using -density ensures it doesn't have metadata scale yet
        convert /tmp/temp_particles.gif -type Grayscale -depth 8 "$TARGET_FILE"
        rm /tmp/temp_particles.gif
    else
        echo "ERROR: Could not download sample image."
        # Create a dummy image if download fails (fallback to prevent total crash)
        convert -size 512x512 xc:white -fill black -draw "circle 100,100 120,120" "$TARGET_FILE"
    fi
fi

# 6. Create Calibration Info File
cat > "$DATA_DIR/calibration_info.txt" << EOF
=== MICROSCOPE CALIBRATION DATA ===
Date: 2024-02-15
Microscope: Olympus BX53M
Objective: 20x Plan Apo
Camera: CMOS 5MP

Pixel Size Calculation:
Sensor Pixel Pitch: 3.45 µm
Magnification: 20x
Binning: 1x1

Effective Scale: 0.1725 µm/pixel

=== ANALYSIS REQUIREMENTS ===
1. Background Subtraction: Rolling Ball (r=50)
2. Threshold: Automatic (e.g. MaxEntropy/Otsu)
3. Min Particle Size: 5 µm²
4. Critical Inclusion Size: 500 µm²
5. QC Criteria: FAIL if > 5 particles exceed critical size
EOF

# Set permissions again
chown -R $USER_GA:$USER_GA "$DATA_DIR"

# 7. Launch Fiji
echo "Launching Fiji..."
# Check if Fiji is already running
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    # Launch via the wrapper script available in the environment
    su - $USER_GA -c "DISPLAY=:1 /home/$USER_GA/launch_fiji.sh" &
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ"; then
            echo "Fiji window detected."
            break
        fi
        sleep 1
    done
fi

# 8. Set Window State
# Maximize window
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "Fiji" 2>/dev/null || DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || true

# 9. Load the image automatically (Optional but helpful for "Starting State")
# Using xdotool to open the specific file simulates user opening, but programmatic load is safer
# We will just leave Fiji open. The description says "Open the specimen image...", so agent does it.
# However, to be nice, we can pre-load it if desired. Let's stick to the description implying agent action.
# But we ensure the file dialog defaults to the right place if possible, or just let agent navigate.

# 10. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="