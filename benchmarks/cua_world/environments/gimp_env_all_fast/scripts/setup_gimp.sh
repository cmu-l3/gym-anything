#!/bin/bash
set -euo pipefail

echo "=== Setting up GIMP configuration ==="

# Set up GIMP directories for users
setup_user_gimp() {
    local username=$1
    local home_dir=$2
    
    echo "Setting up GIMP for user: $username"
    
    # Create GIMP config directory
    sudo -u $username mkdir -p "$home_dir/.config/GIMP/2.10"
    sudo -u $username mkdir -p "$home_dir/.config/GIMP/2.10/brushes"
    sudo -u $username mkdir -p "$home_dir/.config/GIMP/2.10/patterns"
    sudo -u $username mkdir -p "$home_dir/.config/GIMP/2.10/gradients"
    sudo -u $username mkdir -p "$home_dir/.config/GIMP/2.10/scripts"
    sudo -u $username mkdir -p "$home_dir/.config/GIMP/2.10/plug-ins"
    
    # Copy custom GIMP configuration if available
    if [ -f "/workspace/config/gimprc" ]; then
        sudo -u $username cp "/workspace/config/gimprc" "$home_dir/.config/GIMP/2.10/"
        echo "  - Copied custom gimprc"
    fi
    
    # Set up sample projects directory
    sudo -u $username mkdir -p "$home_dir/GimpProjects"
    sudo -u $username mkdir -p "$home_dir/GimpProjects/samples"
    
    # Create a sample project if available
    if [ -d "/workspace/config/sample_projects" ]; then
        sudo -u $username cp -r "/workspace/config/sample_projects/"* "$home_dir/GimpProjects/samples/"
        echo "  - Copied sample projects"
    fi
    
    # Set up desktop shortcut
    sudo -u $username mkdir -p "$home_dir/Desktop"
    cat > "$home_dir/Desktop/GIMP.desktop" << EOF
[Desktop Entry]
Name=GIMP
Comment=GNU Image Manipulation Program
Exec=gimp %U
Icon=gimp
StartupNotify=true
MimeType=image/bmp;image/gif;image/jpeg;image/jpg;image/png;image/tiff;image/x-bmp;image/x-gray;image/x-icb;image/x-ico;image/x-pcx;image/x-png;image/x-portable-anymap;image/x-portable-bitmap;image/x-portable-graymap;image/x-portable-pixmap;image/x-psd;image/x-sgi;image/x-tga;image/x-xbitmap;image/x-xpixmap;image/x-xwindowdump;image/x-xcf;image/x-compressed-xcf;image/x-gimp-gbr;image/x-gimp-pat;image/x-gimp-gih;
Categories=Graphics;2DGraphics;RasterGraphics;GTK;
Type=Application
EOF
    chown $username:$username "$home_dir/Desktop/GIMP.desktop"
    chmod +x "$home_dir/Desktop/GIMP.desktop"
    echo "  - Created desktop shortcut"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_gimp "ga" "/home/ga"
fi

# Setup for artist user 
if id "artist" &>/dev/null; then
    setup_user_gimp "artist" "/home/artist"
fi

# Create a script to launch GIMP with proper settings
sudo cat > /usr/local/bin/launch-gimp << 'EOF'
#!/bin/bash
# Launch GIMP with optimal settings for the container environment

export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Set GIMP environment variables for better performance
export GIMP_PLUGIN_DEBUG_WRAP=none
export GIMP_PLUGIN_DEBUG=none

# Launch GIMP
exec gimp "$@"
EOF

sudo chmod +x /usr/local/bin/launch-gimp

echo "=== GIMP configuration completed ==="

# Just start GIMP for the main VNC user  
# echo "Starting GIMP for ga user..."
# su - ga -c "DISPLAY=:1 gimp > /tmp/gimp.log 2>&1 &"
# sleep 2

echo "GIMP is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'gimp' from terminal"
echo "  - Run 'launch-gimp' for optimized startup"
