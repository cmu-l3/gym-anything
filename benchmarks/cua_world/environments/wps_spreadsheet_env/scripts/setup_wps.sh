#!/bin/bash
# set -euo pipefail

echo "=== Setting up WPS Office Spreadsheet configuration ==="

# Set up WPS Office for a specific user
setup_user_wps() {
    local username=$1
    local home_dir=$2

    echo "Setting up WPS Office Spreadsheet for user: $username"

    # Create WPS Office config directory
    sudo -u $username mkdir -p "$home_dir/.kingsoft/office6/data/backup"
    sudo -u $username mkdir -p "$home_dir/.config/Kingsoft"
    sudo -u $username mkdir -p "$home_dir/Documents"
    sudo -u $username mkdir -p "$home_dir/Documents/results"
    sudo -u $username mkdir -p "$home_dir/Desktop"
    sudo -u $username mkdir -p "$home_dir/Templates"

    # Create WPS configuration to disable first-run dialogs and tips
    WPS_CONFIG_DIR="$home_dir/.kingsoft/office6/data"
    mkdir -p "$WPS_CONFIG_DIR"

    # Create config to disable tips and first-run experience
    cat > "$WPS_CONFIG_DIR/wpsoffice.ini" << 'INIEOF'
[Common]
TipOfTheDay=0
ShowStartCenter=0
ShowSplash=0
[ET]
AutoSave=false
BackupCopy=false
[General]
EULA=accepted
FirstRun=false
INIEOF
    chown -R $username:$username "$home_dir/.kingsoft"
    echo "  - Created WPS configuration"

    # Create Kingsoft config (the primary config WPS reads)
    cat > "$home_dir/.config/Kingsoft/Office.conf" << 'CONFEOF'
[Common]
EULA=true
FirstRun=false
ShowTipOfTheDay=false

[Application]
AutoCheckUpdate=false

[6.0]
common\AcceptedEULA=true
common\Backup\EnableBackup=0
common\autoSwitchSkin=false
common\Backup\BackupInitMode=0
common\Backup\EnableIncBackup=1
common\Backup\EnableTimeBackup=0

[kdcsdk]
NotFirstOpen=true
CONFEOF
    chown -R $username:$username "$home_dir/.config/Kingsoft"
    echo "  - Created alternative config"

    # Set up desktop shortcut for WPS Spreadsheet
    cat > "$home_dir/Desktop/WPS-Spreadsheet.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=WPS Spreadsheet
Comment=Spreadsheet Application
Exec=et %U
Icon=wps-office-et
StartupNotify=true
Terminal=false
MimeType=application/vnd.ms-excel;application/vnd.ms-excel.sheet.macroenabled.12;application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;application/vnd.oasis.opendocument.spreadsheet;
Categories=Office;Spreadsheet;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/WPS-Spreadsheet.desktop"
    chmod +x "$home_dir/Desktop/WPS-Spreadsheet.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script with optimized settings
    cat > "$home_dir/launch_wps_et.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch WPS Spreadsheet with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Set Qt platform theme for better GNOME integration
export QT_QPA_PLATFORMTHEME=gtk2

# Launch WPS Spreadsheet
et "$@" > /tmp/wps_et_$USER.log 2>&1 &

echo "WPS Spreadsheet started"
echo "Log file: /tmp/wps_et_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_wps_et.sh"
    chmod +x "$home_dir/launch_wps_et.sh"
    echo "  - Created launch script"

    # Copy templates if available
    if [ -d "/workspace/config/templates" ]; then
        cp -r /workspace/config/templates/* "$home_dir/Templates/" 2>/dev/null || true
        chown -R $username:$username "$home_dir/Templates"
        echo "  - Copied templates"
    fi

    # Mark the desktop shortcut as trusted (GNOME) - must run as the user with dbus
    su - "$username" -c "dbus-launch gio set $home_dir/Desktop/WPS-Spreadsheet.desktop metadata::trusted true" 2>/dev/null || true
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_wps "ga" "/home/ga"
fi

# Create utility scripts for verifiers
cat > /usr/local/bin/wps-et-headless << 'HEADLESSEOF'
#!/bin/bash
# WPS Office Spreadsheet headless utility
# Note: WPS Office headless support is limited compared to LibreOffice
# This script provides basic file conversion functionality

case "$1" in
    convert-xlsx)
        # WPS uses different command line options
        et --convert-to xlsx "$2" 2>/dev/null
        ;;
    convert-csv)
        et --convert-to csv "$2" 2>/dev/null
        ;;
    *)
        echo "Usage: wps-et-headless <convert-xlsx|convert-csv> <file>"
        echo "Note: WPS Office headless conversion support is limited"
        exit 1
        ;;
esac
HEADLESSEOF
chmod +x /usr/local/bin/wps-et-headless

# Create a script to get window ID for WPS Spreadsheet
cat > /usr/local/bin/get-wps-et-window << 'GETWINEOF'
#!/bin/bash
# Get WPS Spreadsheet window ID
wmctrl -l | grep -i 'WPS Spreadsheet\|\.xlsx\|\.xls\|\.et' | awk '{print $1; exit}'
GETWINEOF
chmod +x /usr/local/bin/get-wps-et-window

# ================================================================
# First-run: Launch WPS to accept EULA and dismiss all startup dialogs
# ================================================================
echo "Performing first-run warm-up launch..."

# Helper: run a command as ga with DISPLAY and XAUTHORITY
run_as_ga() {
    su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; $*"
}

# Wait for desktop session to be ready (GDM auto-login)
echo "  - Waiting for desktop session..."
DESKTOP_TIMEOUT=60
DESKTOP_ELAPSED=0
while [ $DESKTOP_ELAPSED -lt $DESKTOP_TIMEOUT ]; do
    if pgrep -u ga gnome-shell >/dev/null 2>&1; then
        echo "  - Desktop session ready after ${DESKTOP_ELAPSED}s"
        break
    fi
    sleep 3
    DESKTOP_ELAPSED=$((DESKTOP_ELAPSED + 3))
done

# Set up X11 authentication for the ga user
GDM_XAUTH=$(ps aux | grep Xorg | grep -oP '(?<=-auth )\S+' | head -1)
if [ -n "$GDM_XAUTH" ] && [ -f "$GDM_XAUTH" ]; then
    cp "$GDM_XAUTH" /home/ga/.Xauthority
    chown ga:ga /home/ga/.Xauthority
    echo "  - X11 auth configured from GDM ($GDM_XAUTH)"
fi

run_as_ga "xhost +local:" 2>/dev/null || true

# Launch WPS Spreadsheet for warm-up (first-run clears dialogs)
run_as_ga "et &"

# Wait for WPS window to appear
echo "  - Waiting for WPS to load..."
for i in $(seq 1 30); do
    if run_as_ga "wmctrl -l" 2>/dev/null | grep -qi "Spreadsheets\|\.xlsx\|\.et"; then
        echo "  - WPS window detected after ${i}s"
        break
    fi
    sleep 2
done

# Additional wait for dialogs to fully render
sleep 5

# Check if EULA dialog appeared
EULA_WIN=$(run_as_ga "wmctrl -l" 2>/dev/null | grep -i "License Agreement" | awk '{print $1}')
if [ -n "$EULA_WIN" ]; then
    echo "  - EULA dialog detected, auto-accepting..."
    # Click the "agree" checkbox (scaled 430,432 from 1280x720 -> 645,648 at 1920x1080)
    run_as_ga "xdotool mousemove 645 648 click 1"
    sleep 1
    # Click "I confirm" button (scaled 860,432 -> 1290,648)
    run_as_ga "xdotool mousemove 1290 648 click 1"
    sleep 3
    echo "  - EULA accepted"
else
    echo "  - No EULA dialog (config pre-set)"
fi

# Wait for any remaining dialogs to appear
sleep 5

# ----------------------------------------------------------------
# Dismiss all startup dialogs with retry loop (front-to-back order)
# Dialogs: "WPS Office" (default app), "Checking completed!", "System Check"
# ----------------------------------------------------------------
echo "  - Dismissing startup dialogs..."
for _attempt in 1 2 3 4 5; do
    WINDOWS=$(run_as_ga "wmctrl -l" 2>/dev/null)

    # 1. Close "WPS Office" default-app dialog (activate + press Enter on OK button)
    WPS_DIALOG=$(echo "$WINDOWS" | grep -i "WPS Office$" | awk '{print $1}')
    if [ -n "$WPS_DIALOG" ]; then
        echo "    Dismissing 'WPS Office' dialog (attempt $_attempt)..."
        run_as_ga "wmctrl -ia '$WPS_DIALOG'" 2>/dev/null || true
        sleep 0.5
        run_as_ga "xdotool key Return" 2>/dev/null || true
        sleep 2
    fi

    # 2. Close "System Check" dialog (activate + Alt+F4)
    SYSCHECK_WIN=$(echo "$WINDOWS" | grep -i "System Check" | awk '{print $1}')
    if [ -n "$SYSCHECK_WIN" ]; then
        echo "    Dismissing 'System Check' dialog (attempt $_attempt)..."
        run_as_ga "wmctrl -ia '$SYSCHECK_WIN'" 2>/dev/null || true
        sleep 0.5
        run_as_ga "xdotool key alt+F4" 2>/dev/null || true
        sleep 2
    fi

    # 3. Close any "Checking completed" sub-dialog
    CHECK_WIN=$(echo "$WINDOWS" | grep -i "Checking completed" | awk '{print $1}')
    if [ -n "$CHECK_WIN" ]; then
        echo "    Dismissing 'Checking completed' dialog (attempt $_attempt)..."
        run_as_ga "wmctrl -ia '$CHECK_WIN'" 2>/dev/null || true
        sleep 0.5
        run_as_ga "xdotool key Return" 2>/dev/null || true
        sleep 2
    fi

    # Check if all dialogs are gone
    REMAINING=$(run_as_ga "wmctrl -l" 2>/dev/null | grep -ciE "System Check|WPS Office$|Checking completed")
    if [ "$REMAINING" -eq 0 ]; then
        echo "  - All dialogs dismissed after $_attempt attempt(s)"
        break
    fi
    sleep 2
done

# Final fallback: press Escape to close any remaining modal dialogs
run_as_ga "xdotool key Escape" 2>/dev/null || true
sleep 1

# Let WPS save its config (suppresses dialogs on future launches)
sleep 3

# Kill WPS processes specifically (NOT pkill -f "et" which kills gnome-settings-daemon etc.)
pkill -x et 2>/dev/null || true
pkill -x wps 2>/dev/null || true
pkill -x wpp 2>/dev/null || true
pkill -x wpspdf 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
pkill -f "/office6/wps" 2>/dev/null || true
sleep 2

# Update config to suppress future dialogs
WPS_CONF="/home/ga/.config/Kingsoft/Office.conf"
if [ -f "$WPS_CONF" ]; then
    # Add SystemCheck suppression if not present
    if ! grep -q "common\\\\SystemCheck" "$WPS_CONF"; then
        sed -i '/^\[6\.0\]/a common\\SystemCheck\\DontShowAgain=true' "$WPS_CONF" 2>/dev/null || true
    fi
    # Add default office suppression if not present
    if ! grep -q "common\\\\DefaultOffice" "$WPS_CONF"; then
        sed -i '/^\[6\.0\]/a common\\DefaultOffice\\DontAsk=true' "$WPS_CONF" 2>/dev/null || true
    fi
    # Ensure EULA accepted
    if ! grep -q "AcceptedEULA" "$WPS_CONF"; then
        cat >> "$WPS_CONF" << 'APPENDEOF'

[6.0]
common\AcceptedEULA=true
common\Backup\EnableBackup=0
common\autoSwitchSkin=false

[kdcsdk]
NotFirstOpen=true
APPENDEOF
    fi
    chown ga:ga "$WPS_CONF"
fi

echo "  - First-run setup complete"

echo "=== WPS Office Spreadsheet configuration completed ==="
