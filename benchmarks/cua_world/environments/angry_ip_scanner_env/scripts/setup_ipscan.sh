#!/bin/bash
# set -euo pipefail

echo "=== Setting up Angry IP Scanner configuration ==="

setup_user_ipscan() {
    local username=$1
    local home_dir=$2

    echo "Setting up Angry IP Scanner for user: $username"

    # Create Java preferences directory structure for Angry IP Scanner
    # Angry IP Scanner uses Java Preferences API stored in ~/.java/.userPrefs/ipscan/
    sudo -u $username mkdir -p "$home_dir/.java/.userPrefs/ipscan"
    sudo -u $username mkdir -p "$home_dir/.java/.userPrefs/ipscan/gui"
    sudo -u $username mkdir -p "$home_dir/.java/.userPrefs/ipscan/scanner"
    sudo -u $username mkdir -p "$home_dir/.java/.userPrefs/ipscan/favorites"
    sudo -u $username mkdir -p "$home_dir/.java/.userPrefs/ipscan/openers"

    # Copy pre-configured preferences to suppress first-run dialog
    if [ -d "/workspace/config/prefs/ipscan" ]; then
        cp /workspace/config/prefs/ipscan/prefs.xml "$home_dir/.java/.userPrefs/ipscan/prefs.xml"
        cp /workspace/config/prefs/ipscan/gui/prefs.xml "$home_dir/.java/.userPrefs/ipscan/gui/prefs.xml"
        cp /workspace/config/prefs/ipscan/scanner/prefs.xml "$home_dir/.java/.userPrefs/ipscan/scanner/prefs.xml"
        cp /workspace/config/prefs/ipscan/favorites/prefs.xml "$home_dir/.java/.userPrefs/ipscan/favorites/prefs.xml"
        chown -R $username:$username "$home_dir/.java"
        echo "  - Copied pre-configured preferences"
    else
        echo "  - WARNING: Pre-configured preferences not found, creating defaults"
        # Create minimal prefs to suppress first-run
        cat > "$home_dir/.java/.userPrefs/ipscan/prefs.xml" << 'PREFSEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="language" value="en"/>
  <entry key="allowReports" value="false"/>
</map>
PREFSEOF
        cat > "$home_dir/.java/.userPrefs/ipscan/gui/prefs.xml" << 'PREFSEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="firstRun" value="false"/>
  <entry key="versionCheckEnabled" value="false"/>
  <entry key="askScanConfirmation" value="false"/>
</map>
PREFSEOF
        chown -R $username:$username "$home_dir/.java"
    fi

    # Create working directories
    sudo -u $username mkdir -p "$home_dir/Documents"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Copy real data files
    if [ -d "/workspace/data" ]; then
        cp -r /workspace/data "$home_dir/Documents/network_data"
        chown -R $username:$username "$home_dir/Documents/network_data"
        echo "  - Copied network data files"
    fi

    # Create desktop shortcut
    cat > "$home_dir/Desktop/AngryIPScanner.desktop" << DESKTOPEOF
[Desktop Entry]
Name=Angry IP Scanner
Comment=Network Scanner
Exec=ipscan
Icon=ipscan
StartupNotify=true
Terminal=false
Categories=Network;System;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/AngryIPScanner.desktop"
    chmod +x "$home_dir/Desktop/AngryIPScanner.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_ipscan.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch Angry IP Scanner
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Launch Angry IP Scanner
setsid ipscan "$@" > /tmp/ipscan_$USER.log 2>&1 &

echo "Angry IP Scanner started"
echo "Log file: /tmp/ipscan_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_ipscan.sh"
    chmod +x "$home_dir/launch_ipscan.sh"
    echo "  - Created launch script"
}

# Setup for ga user
if id "ga" &>/dev/null; then
    setup_user_ipscan "ga" "/home/ga"
fi

# Ensure network services are running (these serve as real scan targets)
echo "Ensuring network services are running..."
systemctl start ssh 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Warm-up launch: start ipscan once to clear any remaining first-run state,
# then kill it so task scripts can launch it fresh
echo "Performing warm-up launch to clear first-run state..."
su - ga -c "DISPLAY=:1 setsid ipscan > /tmp/ipscan_warmup.log 2>&1 &"
sleep 10

# Check if ipscan window appeared and dismiss Getting Started dialog
# NOTE: SWT dialogs do NOT respond to xdotool key Escape; use wmctrl -c instead
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Angry IP Scanner\|ipscan"; then
    echo "  - Warm-up: Window appeared"
    # Dismiss Getting Started dialog if present
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "Getting Started"; then
        echo "  - Dismissing Getting Started dialog..."
        DISPLAY=:1 wmctrl -c "Getting Started" 2>/dev/null || true
        sleep 2
    fi
fi

# Gracefully quit ipscan so it saves preferences (SIGTERM, not SIGKILL)
kill $(pgrep -f "ipscan-linux64") 2>/dev/null || true
sleep 3
# Force kill if still running
pkill -9 -f ipscan 2>/dev/null || true
sleep 2

echo "=== Angry IP Scanner configuration completed ==="
echo "Angry IP Scanner is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'ipscan' from terminal"
echo "  - Run '~/launch_ipscan.sh' for optimized launch"
