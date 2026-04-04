#!/bin/bash
set -euo pipefail

echo "=== Setting up Google Earth Pro configuration ==="

setup_user_earth() {
    local username=$1
    local home_dir=$2

    echo "Setting up Google Earth for user: $username"

    # Create Google Earth directories
    sudo -u $username mkdir -p "$home_dir/.config/Google"
    sudo -u $username mkdir -p "$home_dir/.googleearth"

    # Create desktop shortcut
    sudo -u $username mkdir -p "$home_dir/Desktop"
    cat > "$home_dir/Desktop/GoogleEarth.desktop" << 'EOF'
[Desktop Entry]
Name=Google Earth Pro
Comment=Explore the world
Exec=google-earth-pro %f
Icon=google-earth
Type=Application
Categories=Science;Geography;Education;
Terminal=false
EOF
    chown $username:$username "$home_dir/Desktop/GoogleEarth.desktop"
    chmod +x "$home_dir/Desktop/GoogleEarth.desktop"

    # Suppress first-run dialogs/tips if config exists
    if [ -d "/workspace/config/googleearth" ]; then
        cp -r /workspace/config/googleearth/* "$home_dir/.googleearth/" 2>/dev/null || true
        chown -R $username:$username "$home_dir/.googleearth"
    fi
}

# Setup for ga user
if id "ga" &>/dev/null; then
    setup_user_earth "ga" "/home/ga"
fi

# Create launcher script
cat > /usr/local/bin/launch-google-earth << 'EOF'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true
exec google-earth-pro "$@"
EOF
chmod +x /usr/local/bin/launch-google-earth

echo "=== Google Earth Pro setup completed ==="
