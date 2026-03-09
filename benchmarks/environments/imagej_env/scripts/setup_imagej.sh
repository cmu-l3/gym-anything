#!/bin/bash
# set -euo pipefail

echo "=== Setting up Fiji (ImageJ) configuration ==="

# Set up Fiji for a specific user
setup_user_fiji() {
    local username=$1
    local home_dir=$2

    echo "Setting up Fiji for user: $username"

    # Give recursive full permissions to cache
    sudo chmod -R 777 /home/$username/.cache 2>/dev/null || true

    # Create ImageJ/Fiji directories
    sudo -u $username mkdir -p "$home_dir/.imagej"
    sudo -u $username mkdir -p "$home_dir/.config/Fiji"
    sudo -u $username mkdir -p "$home_dir/ImageJ_Data"
    sudo -u $username mkdir -p "$home_dir/ImageJ_Data/raw"
    sudo -u $username mkdir -p "$home_dir/ImageJ_Data/processed"
    sudo -u $username mkdir -p "$home_dir/ImageJ_Data/results"
    sudo -u $username mkdir -p "$home_dir/ImageJ_Data/measurements"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Copy sample images to user directory
    echo "  - Copying sample images..."
    if [ -d "/opt/imagej_samples" ]; then
        cp -r /opt/imagej_samples/* "$home_dir/ImageJ_Data/raw/" 2>/dev/null || true
        chown -R $username:$username "$home_dir/ImageJ_Data"
    fi

    # Create Fiji preferences file to skip first-run dialogs
    # Fiji uses IJ_Prefs.txt in the fiji installation directory or user's home
    cat > "$home_dir/.imagej/IJ_Prefs.txt" << 'PREFEOF'
.imagej.prefs.firstRun=false
.imagej.prefs.updateCheckOnStartup=false
.fiji.prefs.updateCheckOnStartup=false
ij.y=0
ij.x=0
proxy.server=
proxy.port=-1
PREFEOF
    chown $username:$username "$home_dir/.imagej/IJ_Prefs.txt"
    echo "  - Created ImageJ preferences"

    # Also copy prefs to Fiji's app directory if it exists
    if [ -d "/opt/fiji/Fiji.app" ]; then
        cp "$home_dir/.imagej/IJ_Prefs.txt" "/opt/fiji/Fiji.app/IJ_Prefs.txt" 2>/dev/null || true
    fi

    # Create desktop shortcut
    cat > "$home_dir/Desktop/Fiji.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=Fiji (ImageJ)
Comment=Scientific Image Processing and Analysis
Exec=/usr/local/bin/fiji
Icon=applications-science
StartupNotify=true
Terminal=false
Categories=Science;Biology;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/Fiji.desktop"
    chmod +x "$home_dir/Desktop/Fiji.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_fiji.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch Fiji with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Set memory options (Fiji needs more memory for large images)
export _JAVA_OPTIONS="-Xmx4g"

# Find Fiji executable
FIJI_PATH=""
for path in \
    "/usr/local/bin/fiji" \
    "/opt/fiji/Fiji.app/ImageJ-linux64" \
    "/opt/fiji/ImageJ-linux64"; do
    if [ -x "$path" ]; then
        FIJI_PATH="$path"
        break
    fi
done

if [ -z "$FIJI_PATH" ]; then
    echo "Fiji not found!"
    echo "Checked locations:"
    ls -la /opt/fiji/ 2>/dev/null || echo "  /opt/fiji not found"
    exit 1
fi

echo "Found Fiji at: $FIJI_PATH"

# Launch Fiji
cd "$(dirname "$FIJI_PATH")" 2>/dev/null || cd /opt/fiji
"$FIJI_PATH" "$@" > /tmp/fiji_$USER.log 2>&1 &

echo "Fiji started (PID: $!)"
echo "Log file: /tmp/fiji_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_fiji.sh"
    chmod +x "$home_dir/launch_fiji.sh"
    echo "  - Created launch script"

    # Create macro for opening sample images
    cat > "$home_dir/open_blobs.ijm" << 'MACROEOF'
// Open the blobs sample image (built into Fiji)
run("Blobs (25K)");
MACROEOF
    chown $username:$username "$home_dir/open_blobs.ijm"
    chmod 644 "$home_dir/open_blobs.ijm"

    # Create utility script for image info
    cat > "/usr/local/bin/image-info" << 'IMGINFO'
#!/usr/bin/env python3
"""Display image file information."""
import sys
try:
    from PIL import Image
    import numpy as np

    if len(sys.argv) < 2:
        print("Usage: image-info <image_file>")
        sys.exit(1)

    filename = sys.argv[1]
    img = Image.open(filename)

    print(f"=== Image File: {filename} ===")
    print(f"Format: {img.format}")
    print(f"Mode: {img.mode}")
    print(f"Size: {img.size[0]} x {img.size[1]} pixels")

    if hasattr(img, 'n_frames'):
        print(f"Frames: {img.n_frames}")

    # Convert to numpy for statistics
    arr = np.array(img)
    print(f"Data type: {arr.dtype}")
    print(f"Min value: {arr.min()}")
    print(f"Max value: {arr.max()}")
    print(f"Mean value: {arr.mean():.2f}")

except ImportError as e:
    print(f"Missing library: {e}")
except Exception as e:
    print(f"Error: {e}")
IMGINFO
    chmod +x /usr/local/bin/image-info

    # Set proper permissions
    chown -R $username:$username "$home_dir/.imagej"
    chown -R $username:$username "$home_dir/.config/Fiji" 2>/dev/null || true
    chown -R $username:$username "$home_dir/ImageJ_Data"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_fiji "ga" "/home/ga"
fi

echo "=== Fiji (ImageJ) configuration completed ==="

# Do not auto-launch Fiji here - let task scripts handle launching
echo "Fiji is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'fiji' or 'imagej' from terminal"
echo "  - Run '~/launch_fiji.sh' for optimized launch"
echo "  - Use 'image-info <file>' to inspect image files"
echo ""
echo "Sample images are in ~/ImageJ_Data/raw/"
echo "Built-in samples available via File > Open Samples"
