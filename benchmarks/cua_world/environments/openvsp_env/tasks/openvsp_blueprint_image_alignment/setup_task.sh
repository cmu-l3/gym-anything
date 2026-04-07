#!/bin/bash
# Setup script for openvsp_blueprint_image_alignment task
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_blueprint_image_alignment ==="

# Ensure working directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop

# 1. Provide real data (P-51D Mustang Blueprint)
IMAGE_PATH="$MODELS_DIR/p51_top_view.jpg"
IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/4/4b/North_American_P-51D_Mustang_3-view_silhouette.png"

echo "Downloading real blueprint image..."
if ! wget -q -O "$IMAGE_PATH" "$IMAGE_URL"; then
    echo "Warning: Failed to download from Wikimedia. Generating fallback blueprint..."
    # Fallback to an ImageMagick generated placeholder if network is blocked
    convert -size 2820x1000 xc:white -fill blue -draw "line 0,500 2820,500" \
            -fill black -pointsize 48 -gravity center -draw "text 0,0 'P-51D MUSTANG TOP VIEW (FALLBACK)'" \
            "$IMAGE_PATH"
fi
chmod 644 "$IMAGE_PATH"

# 2. Write the blueprint specification document
SPEC_PATH="$MODELS_DIR/blueprint_setup.txt"
cat > "$SPEC_PATH" << 'SPEC_EOF'
================================================
P-51D MUSTANG BLUEPRINT SETUP
================================================
Image File: /home/ga/Documents/OpenVSP/p51_top_view.jpg
Target Viewport: Top

Calibration Data:
- Real-world Wingspan: 11.28 meters
- In the provided image, the distance from the left wingtip to the right wingtip is exactly 2820 pixels.
- The OpenVSP Image Scale parameter defines the physical Model Units per Pixel.

Instructions:
1. Open the Background image dialog (Window -> Background).
2. Load the image into the Top viewport section.
3. Calculate the correct Image Scale based on the calibration data.
4. Set the Scale value in the dialog.
5. Save the OpenVSP model to /home/ga/Documents/OpenVSP/p51_workspace.vsp3
================================================
SPEC_EOF
chmod 644 "$SPEC_PATH"

# Create a convenient desktop shortcut to the spec
ln -sf "$SPEC_PATH" /home/ga/Desktop/blueprint_setup.txt

# Remove any stale outputs
rm -f "$MODELS_DIR/p51_workspace.vsp3"
rm -f /tmp/openvsp_blueprint_alignment_result.json

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Kill any running OpenVSP instance
kill_openvsp

# Launch OpenVSP blank
launch_openvsp
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear in time — agent may need to launch it manually"
    take_screenshot /tmp/task_start_screenshot.png
fi

chown -R ga:ga "$MODELS_DIR"

echo "=== Setup complete ==="