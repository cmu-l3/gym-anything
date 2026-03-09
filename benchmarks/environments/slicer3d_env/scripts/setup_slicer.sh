#!/bin/bash
# set -euo pipefail

echo "=== Setting up 3D Slicer configuration ==="

# Check if Slicer installation was incomplete
SLICER_INSTALL_DIR="/opt/Slicer"
if [ -f /tmp/slicer_download_incomplete ] || [ ! -x "$SLICER_INSTALL_DIR/Slicer" ]; then
    echo "Slicer installation incomplete, attempting to complete..."
    rm -f /tmp/slicer_download_incomplete

    # Try to download and install Slicer now
    cd /tmp
    DOWNLOAD_URL="https://download.slicer.org/download?os=linux&stability=release"

    if command -v aria2c &> /dev/null; then
        aria2c -x 4 -s 4 -k 1M --max-tries=2 --timeout=240 --connect-timeout=30 \
            -o slicer.tar.gz "$DOWNLOAD_URL" 2>/dev/null || true
    else
        curl -L -o slicer.tar.gz --connect-timeout 30 --max-time 240 \
            "$DOWNLOAD_URL" 2>/dev/null || true
    fi

    if [ -f slicer.tar.gz ] && [ $(stat -c%s slicer.tar.gz 2>/dev/null || echo 0) -gt 100000000 ]; then
        echo "Download successful, extracting..."
        mkdir -p "$SLICER_INSTALL_DIR"
        tar -xzf slicer.tar.gz -C "$SLICER_INSTALL_DIR" --strip-components=1
        ln -sf "$SLICER_INSTALL_DIR/Slicer" /usr/local/bin/Slicer
        ln -sf "$SLICER_INSTALL_DIR/Slicer" /usr/local/bin/slicer
        rm -f slicer.tar.gz
        echo "Slicer installation completed!"
    else
        echo "WARNING: Could not complete Slicer installation"
    fi
fi

# Set up 3D Slicer for a specific user
setup_user_slicer() {
    local username=$1
    local home_dir=$2

    echo "Setting up 3D Slicer for user: $username"

    # Give recursive full permissions to the user's cache
    sudo chmod -R 777 /home/$username/.cache 2>/dev/null || true

    # Create Slicer directories
    mkdir -p "$home_dir/.config/NA-MIC"
    mkdir -p "$home_dir/.local/share/NA-MIC"
    mkdir -p "$home_dir/Documents/SlicerData"
    mkdir -p "$home_dir/Documents/SlicerData/SampleData"
    mkdir -p "$home_dir/Documents/SlicerData/Screenshots"
    mkdir -p "$home_dir/Documents/SlicerData/Exports"
    mkdir -p "$home_dir/Desktop"
    chown -R $username:$username "$home_dir/.config"
    chown -R $username:$username "$home_dir/.local"
    chown -R $username:$username "$home_dir/Documents"
    chown -R $username:$username "$home_dir/Desktop"

    # Create default Slicer settings to disable first-run dialogs and enable quiet start
    # Slicer uses INI-style config files
    SLICER_CONFIG_DIR="$home_dir/.config/NA-MIC"

    cat > "$SLICER_CONFIG_DIR/Slicer.ini" << 'SLICERCONF'
[General]
language=en
geometry=@ByteArray(\x1\xd9\xd0\xcb\0\x3\0\0\0\0\0\0\0\0\0\0\0\0\a\x7f\0\0\x4\x37\0\0\0\0\0\0\0\0\0\0\a\x7f\0\0\x4\x37\0\0\0\0\0\x2\0\0\a\x80\0\0\0\0\0\0\0\0\0\0\a\x7f\0\0\x4\x37)
windowState=@ByteArray(\0\0\0\xff\0\0\0\0\xfd\0\0\0\0\0\0\a\x80\0\0\x3\xd7\0\0\0\x4\0\0\0\x4\0\0\0\b\0\0\0\b\xfc\0\0\0\0)

[ctkPathLineEdit]
showBrowseButton=true
showHistoryButton=true

[Modules]
HomeModule=Welcome
FavoriteModules=Data, Volumes, Models, Transforms, Markups, Segment Editor, SegmentStatistics

[Privacy]
checkForUpdatesEnabled=false
sendUsageStatisticsEnabled=false

[RecentlyLoadedFiles]
maximumNumberOfFilesToKeep=10

[ScreenCapture]
outputDirectory=/home/ga/Documents/SlicerData/Screenshots
imageFileFormat=png

[ApplicationSettings]
ConfirmExit=false
ShowWelcomeMessage=false
ApplicationExitConfirmationRestricted=false
SLICERCONF

    # Replace /home/ga with actual home dir
    sed -i "s|/home/ga|$home_dir|g" "$SLICER_CONFIG_DIR/Slicer.ini"
    chown $username:$username "$SLICER_CONFIG_DIR/Slicer.ini"
    chown -R $username:$username "$SLICER_CONFIG_DIR"
    echo "  - Created Slicer configuration"

    # Download sample DICOM data for tasks
    echo "  - Downloading sample medical imaging data..."

    # Download MRHead sample data (a standard 3D Slicer test dataset)
    # This is a small MRI brain scan that comes with Slicer's sample data
    SAMPLE_DIR="$home_dir/Documents/SlicerData/SampleData"

    # Download sample data from Slicer's testing data repository
    cd "$SAMPLE_DIR"

    # MRHead - small brain MRI (~4MB)
    # Using multiple URLs for reliability
    MRHEAD_DOWNLOADED=false
    echo "  - Downloading MRHead sample..."

    # Try GitHub releases first
    if curl -L -o MRHead.nrrd --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null; then
        if [ -f MRHead.nrrd ] && [ $(stat -c%s MRHead.nrrd 2>/dev/null || echo 0) -gt 1000000 ]; then
            echo "    Downloaded MRHead.nrrd successfully"
            MRHEAD_DOWNLOADED=true
        fi
    fi

    # Try alternative URL if first failed
    if [ "$MRHEAD_DOWNLOADED" = "false" ]; then
        echo "    Trying alternative URL for MRHead..."
        if wget --timeout=120 -O MRHead.nrrd \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null; then
            if [ -f MRHead.nrrd ] && [ $(stat -c%s MRHead.nrrd 2>/dev/null || echo 0) -gt 1000000 ]; then
                echo "    Downloaded MRHead.nrrd successfully"
                MRHEAD_DOWNLOADED=true
            fi
        fi
    fi

    # Generate synthetic data as last resort
    if [ "$MRHEAD_DOWNLOADED" = "false" ]; then
        echo "    Warning: Could not download MRHead, generating synthetic NRRD data..."
        python3 << 'PYEOF'
import numpy as np

try:
    # Create a simple 3D synthetic brain-like volume
    shape = (64, 64, 64)
    data = np.zeros(shape, dtype=np.int16)

    # Create a spherical "brain" structure with varying intensities
    center = np.array(shape) / 2
    for x in range(shape[0]):
        for y in range(shape[1]):
            for z in range(shape[2]):
                dist = np.sqrt((x - center[0])**2 + (y - center[1])**2 + (z - center[2])**2)
                if dist < 25:
                    data[x, y, z] = 800 + int(200 * np.sin(dist / 3))
                elif dist < 28:
                    data[x, y, z] = 1200  # "skull"

    # Write as NRRD format (simple ASCII header + raw binary)
    with open('/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd', 'wb') as f:
        header = """NRRD0004
type: int16
dimension: 3
space: left-posterior-superior
sizes: 64 64 64
space directions: (2,0,0) (0,2,0) (0,0,2)
kinds: domain domain domain
endian: little
encoding: raw
space origin: (-64,-64,-64)

"""
        f.write(header.encode('ascii'))
        f.write(data.tobytes())
    print("    Created synthetic MRHead.nrrd")
except Exception as e:
    print(f"    Could not create synthetic data: {e}")
PYEOF
    fi

    # CTChest sample - larger file (~42MB), optional
    echo "  - CTChest.nrrd already present or downloading..."
    if [ ! -f CTChest.nrrd ] || [ $(stat -c%s CTChest.nrrd 2>/dev/null || echo 0) -lt 1000000 ]; then
        curl -L -o CTChest.nrrd --connect-timeout 30 --max-time 300 \
            "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/4507b664690840abb6cb9af2d919377ffc4ef75b167cb6fd0f747befdb12e38e" 2>/dev/null || \
            echo "    Warning: Could not download CTChest sample (optional)"
    fi

    # Set permissions
    chown -R $username:$username "$home_dir/Documents/SlicerData"

    # Create desktop shortcut
    cat > "$home_dir/Desktop/Slicer.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=3D Slicer
Comment=Medical Image Visualization and Analysis
Exec=/opt/Slicer/Slicer %F
Icon=/opt/Slicer/lib/Slicer-5.6/Slicer.iconset/icon_256x256.png
StartupNotify=true
Terminal=false
MimeType=application/dicom;image/nrrd;
Categories=Graphics;MedicalSoftware;Science;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/Slicer.desktop"
    chmod +x "$home_dir/Desktop/Slicer.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_slicer.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch 3D Slicer with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Set OpenGL to software rendering if needed (for VMs without GPU)
# export LIBGL_ALWAYS_SOFTWARE=1

# Launch Slicer
/opt/Slicer/Slicer "$@" > /tmp/slicer_$USER.log 2>&1 &

echo "3D Slicer started"
echo "Log file: /tmp/slicer_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_slicer.sh"
    chmod +x "$home_dir/launch_slicer.sh"
    echo "  - Created launch script"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_slicer "ga" "/home/ga"
fi

# Create utility scripts
cat > /usr/local/bin/slicer-info << 'INFOEOF'
#!/bin/bash
# 3D Slicer info utility
echo "=== 3D Slicer Information ==="
echo "Installation: /opt/Slicer"
echo "Version: $(/opt/Slicer/Slicer --version 2>/dev/null | head -1 || echo 'Unknown')"
echo "Sample data: /home/ga/Documents/SlicerData/SampleData/"
echo ""
echo "Available sample files:"
ls -la /home/ga/Documents/SlicerData/SampleData/ 2>/dev/null || echo "No sample files found"
INFOEOF
chmod +x /usr/local/bin/slicer-info

echo "=== 3D Slicer configuration completed ==="

# Do not auto-launch Slicer here - let task scripts handle launching
echo "3D Slicer is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run '/opt/Slicer/Slicer' from terminal"
echo "  - Run '~/launch_slicer.sh <file>' for optimized launch"
echo "  - Use 'slicer-info' to check installation"
