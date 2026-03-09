#!/bin/bash
# set -euo pipefail

echo "=== Setting up GeoGebra configuration ==="

# Set up GeoGebra for a specific user
setup_user_geogebra() {
    local username=$1
    local home_dir=$2

    echo "Setting up GeoGebra for user: $username"

    # Give recursive full permissions to the user's cache
    sudo chmod -R 777 /home/$username/.cache 2>/dev/null || true

    # Create GeoGebra config and data directories
    sudo -u $username mkdir -p "$home_dir/.geogebra"
    sudo -u $username mkdir -p "$home_dir/.local/share/geogebra"
    sudo -u $username mkdir -p "$home_dir/.cache/geogebra"

    # Create working directories for GeoGebra files
    sudo -u $username mkdir -p "$home_dir/Documents/GeoGebra"
    sudo -u $username mkdir -p "$home_dir/Documents/GeoGebra/exports"
    sudo -u $username mkdir -p "$home_dir/Documents/GeoGebra/projects"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Create GeoGebra preferences to disable first-run dialogs and tips
    # GeoGebra Classic 6 stores preferences in ~/.geogebra
    cat > "$home_dir/.geogebra/prefs.xml" << 'PREFSEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE preferences SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<preferences EXTERNAL_XML_VERSION="1.0">
  <root type="user">
    <map/>
    <node name="geogebra">
      <map>
        <entry key="showToolBarHelp" value="false"/>
        <entry key="showInputHelp" value="false"/>
        <entry key="firstVersionUsed" value="6.0.0.0"/>
        <entry key="showAlgebraInput" value="true"/>
        <entry key="showResetIcon" value="false"/>
        <entry key="showMenuBar" value="true"/>
        <entry key="showToolBar" value="true"/>
        <entry key="showInputField" value="true"/>
        <entry key="useLocalDigits" value="false"/>
        <entry key="useLocalLabels" value="true"/>
        <entry key="rightClick" value="true"/>
        <entry key="labelDragging" value="true"/>
        <entry key="enableUndo" value="true"/>
        <entry key="fontSize" value="16"/>
        <entry key="tooltipTimeout" value="0"/>
        <entry key="perspectivesTabs" value="true"/>
      </map>
    </node>
  </root>
</preferences>
PREFSEOF
    chown $username:$username "$home_dir/.geogebra/prefs.xml"
    echo "  - Created GeoGebra preferences"

    # Set proper permissions for all directories
    chown -R $username:$username "$home_dir/Documents/GeoGebra"
    chown -R $username:$username "$home_dir/.geogebra"
    chown -R $username:$username "$home_dir/.local/share/geogebra" 2>/dev/null || true
    chown -R $username:$username "$home_dir/.cache/geogebra" 2>/dev/null || true

    # Create desktop shortcut
    # Try to find the GeoGebra executable
    GEOGEBRA_EXEC=""
    if [ -x "/usr/bin/geogebra-classic" ]; then
        GEOGEBRA_EXEC="geogebra-classic"
    elif [ -x "/usr/bin/geogebra" ]; then
        GEOGEBRA_EXEC="geogebra"
    elif command -v flatpak &> /dev/null && flatpak list | grep -q geogebra; then
        GEOGEBRA_EXEC="flatpak run org.geogebra.GeoGebra"
    fi

    if [ -n "$GEOGEBRA_EXEC" ]; then
        cat > "$home_dir/Desktop/GeoGebra.desktop" << DESKTOPEOF
[Desktop Entry]
Name=GeoGebra Classic
Comment=Dynamic mathematics software
Exec=$GEOGEBRA_EXEC %F
Icon=geogebra
StartupNotify=true
Terminal=false
MimeType=application/x-geogebra;
Categories=Education;Math;
Type=Application
DESKTOPEOF
        chown $username:$username "$home_dir/Desktop/GeoGebra.desktop"
        chmod +x "$home_dir/Desktop/GeoGebra.desktop"
        echo "  - Created desktop shortcut"
    fi

    # Create launch script
    cat > "$home_dir/launch_geogebra.sh" << LAUNCHEOF
#!/bin/bash
# Launch GeoGebra with optimized settings
export DISPLAY=\${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Launch GeoGebra
if [ -x "/usr/bin/geogebra-classic" ]; then
    geogebra-classic "\$@" > /tmp/geogebra_\$USER.log 2>&1 &
elif [ -x "/usr/bin/geogebra" ]; then
    geogebra "\$@" > /tmp/geogebra_\$USER.log 2>&1 &
elif command -v flatpak &> /dev/null && flatpak list | grep -q geogebra; then
    flatpak run org.geogebra.GeoGebra "\$@" > /tmp/geogebra_\$USER.log 2>&1 &
else
    echo "GeoGebra not found!"
    exit 1
fi

echo "GeoGebra started"
echo "Log file: /tmp/geogebra_\$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_geogebra.sh"
    chmod +x "$home_dir/launch_geogebra.sh"
    echo "  - Created launch script"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_geogebra "ga" "/home/ga"
fi

echo "=== GeoGebra configuration completed ==="

# Do not auto-launch GeoGebra here - let task scripts handle launching
echo "GeoGebra is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'geogebra-classic' or 'geogebra' from terminal"
echo "  - Run '~/launch_geogebra.sh <file>' for optimized launch"
