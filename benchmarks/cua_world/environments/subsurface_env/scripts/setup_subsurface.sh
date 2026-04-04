#!/bin/bash
set -euo pipefail

echo "=== Setting up Subsurface Dive Log ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# =====================================================================
# 1. Set up user home directories and documents folder
# =====================================================================
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# =====================================================================
# 2. Pre-configure Subsurface to suppress first-run dialogs
# Subsurface uses Qt settings stored in ~/.config/Subsurface/Subsurface.conf
# Key settings: disable cloud sync, disable update checks
# =====================================================================
mkdir -p /home/ga/.config/Subsurface
cat > /home/ga/.config/Subsurface/Subsurface.conf << 'CONF_EOF'
[General]
CloudEnabled=false
AutoCloudStorage=false
CheckForUpdates=false
BackgroundCheck=false
DisplayedMonth=7
DisplayedYear=2011
DefaultFilename=/home/ga/Documents/dives.ssrf

[Units]
pressure=0
temperature=0
length=0
volume=0
weight=0
time=0
verticalspeedtime=0

[ColorSetting]
theme=0

[UpdateManager]
DontCheckForUpdates=true
NextCheck=2461107

[Recent_Files]
File_1=/home/ga/Documents/dives.ssrf
CONF_EOF

chown -R ga:ga /home/ga/.config/Subsurface

# =====================================================================
# 3. Copy sample data to user's Documents folder
# =====================================================================
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf
echo "Sample dive data installed: $(stat -c%s /home/ga/Documents/dives.ssrf) bytes"

# =====================================================================
# 4. Warm-up launch: start Subsurface once to accept any remaining
#    first-run dialogs and ensure settings are persisted
# =====================================================================
echo "Performing warm-up launch to dismiss any first-run dialogs..."

# Ensure X server is accessible
xhost +local: 2>/dev/null || true

# Launch Subsurface briefly as ga user
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf >/home/ga/subsurface_warmup.log 2>&1 &"
sleep 8

# Dismiss any welcome/update dialogs with Escape, then Enter
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 2

# Kill warm-up instance
pkill -f subsurface 2>/dev/null || true
sleep 3

# =====================================================================
# 5. Create a desktop shortcut for Subsurface
# =====================================================================
mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/Subsurface.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Name=Subsurface
Comment=Dive Log Application
Exec=subsurface /home/ga/Documents/dives.ssrf
Icon=subsurface
Type=Application
Categories=Science;Sports;Education;
Terminal=false
DESKTOP_EOF

chown ga:ga /home/ga/Desktop/Subsurface.desktop
chmod +x /home/ga/Desktop/Subsurface.desktop

echo "=== Subsurface setup complete ==="
