#!/bin/bash
# set -euo pipefail

echo "=== Setting up WPS Office Writer configuration ==="

# Set up WPS Office for a specific user
setup_user_wps() {
    local username=$1
    local home_dir=$2

    echo "Setting up WPS Office Writer for user: $username"

    # Create WPS Office config directory
    sudo -u $username mkdir -p "$home_dir/.kingsoft/office6/data/backup"
    sudo -u $username mkdir -p "$home_dir/.config/Kingsoft"
    sudo -u $username mkdir -p "$home_dir/Documents"
    sudo -u $username mkdir -p "$home_dir/Documents/results"
    sudo -u $username mkdir -p "$home_dir/Desktop"
    sudo -u $username mkdir -p "$home_dir/Templates"

    # Create WPS configuration to disable first-run dialogs and tips
    # The configuration file path varies by version, try multiple locations
    WPS_CONFIG_DIR="$home_dir/.kingsoft/office6/data"
    mkdir -p "$WPS_CONFIG_DIR"

    # Create config to disable tips and first-run experience
    cat > "$WPS_CONFIG_DIR/wpsoffice.ini" << 'INIEOF'
[Common]
TipOfTheDay=0
ShowStartCenter=0
ShowSplash=0
[Writer]
AutoSave=false
BackupCopy=false
[General]
EULA=accepted
FirstRun=false
INIEOF
    chown -R $username:$username "$home_dir/.kingsoft"
    echo "  - Created WPS configuration"

    # Create Kingsoft config (alternative location)
    cat > "$home_dir/.config/Kingsoft/Office.conf" << 'CONFEOF'
[Common]
EULA=true
FirstRun=false
ShowTipOfTheDay=false
[Application]
AutoCheckUpdate=false
CONFEOF
    chown -R $username:$username "$home_dir/.config/Kingsoft"
    echo "  - Created alternative config"

    # Set up desktop shortcut for WPS Writer
    cat > "$home_dir/Desktop/WPS-Writer.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=WPS Writer
Comment=Word Processing Application
Exec=wps %U
Icon=wps-office-wpsmain
StartupNotify=true
Terminal=false
MimeType=application/vnd.ms-word;application/msword;application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/vnd.oasis.opendocument.text;
Categories=Office;WordProcessor;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/WPS-Writer.desktop"
    chmod +x "$home_dir/Desktop/WPS-Writer.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script with optimized settings
    cat > "$home_dir/launch_wps.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch WPS Writer with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Set Qt platform theme for better GNOME integration
export QT_QPA_PLATFORMTHEME=gtk2

# Launch WPS Writer
wps "$@" > /tmp/wps_$USER.log 2>&1 &

echo "WPS Writer started"
echo "Log file: /tmp/wps_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_wps.sh"
    chmod +x "$home_dir/launch_wps.sh"
    echo "  - Created launch script"

    # Copy templates if available
    if [ -d "/workspace/config/templates" ]; then
        cp -r /workspace/config/templates/* "$home_dir/Templates/" 2>/dev/null || true
        chown -R $username:$username "$home_dir/Templates"
        echo "  - Copied templates"
    fi

    # Mark the desktop shortcut as trusted (GNOME)
    gio set "$home_dir/Desktop/WPS-Writer.desktop" metadata::trusted true 2>/dev/null || true
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_wps "ga" "/home/ga"
fi

# Create utility scripts for verifiers
cat > /usr/local/bin/wps-headless << 'HEADLESSEOF'
#!/bin/bash
# WPS Office headless utility
# Note: WPS Office headless support is limited compared to LibreOffice
# This script provides basic file conversion functionality

case "$1" in
    convert-pdf)
        # WPS uses different command line options
        wps --output-format=pdf "$2" 2>/dev/null
        ;;
    convert-docx)
        wps --output-format=docx "$2" 2>/dev/null
        ;;
    *)
        echo "Usage: wps-headless <convert-pdf|convert-docx> <file>"
        echo "Note: WPS Office headless conversion support is limited"
        exit 1
        ;;
esac
HEADLESSEOF
chmod +x /usr/local/bin/wps-headless

# Create a script to get window ID for WPS Writer
cat > /usr/local/bin/get-wps-window << 'GETWINEOF'
#!/bin/bash
# Get WPS Writer window ID
wmctrl -l | grep -i 'WPS Writer\|\.docx\|\.doc\|\.wps' | awk '{print $1; exit}'
GETWINEOF
chmod +x /usr/local/bin/get-wps-window

echo "=== WPS Office Writer configuration completed ==="

echo "WPS Office Writer is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'wps' from terminal"
echo "  - Run '~/launch_wps.sh <file>' for optimized launch"
echo "  - Use 'et' for spreadsheets, 'wpp' for presentations"
