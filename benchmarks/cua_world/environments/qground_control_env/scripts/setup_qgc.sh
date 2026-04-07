#!/bin/bash
set -e

echo "=== Setting up QGroundControl + ArduPilot SITL ==="

# ── 1. Wait for desktop to be ready ─────────────────────────────────────
echo "--- Waiting for desktop readiness ---"
sleep 5

# ── 1a. Hide GNOME dock to prevent it from overlapping QGC ─────────────
echo "--- Hiding GNOME dock ---"
su - ga -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false" 2>/dev/null || true
su - ga -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus gsettings set org.gnome.shell.extensions.dash-to-dock autohide true" 2>/dev/null || true
su - ga -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus gsettings set org.gnome.shell.extensions.dash-to-dock intellihide false" 2>/dev/null || true

# ── 1b. Switch netplan renderer to NetworkManager ─────────────────────────
# Qt 6 (QGC v5) checks NetworkManager D-Bus for connectivity status.
# The base image uses systemd-networkd (netplan default), so NM sees
# interfaces as "unmanaged" and Qt reports "Network Not Available",
# preventing QGC from fetching map tiles even though internet works.
# Fix: Change netplan renderer from networkd to NetworkManager.
echo "--- Configuring NetworkManager for Qt connectivity detection ---"

# Find the primary ethernet interface
PRIMARY_IFACE=$(ip -o link show | awk -F': ' '!/lo/{print $2; exit}')
PRIMARY_MAC=$(ip -o link show "$PRIMARY_IFACE" 2>/dev/null | grep -oP 'link/ether \K[^ ]+')
echo "Primary interface: $PRIMARY_IFACE (MAC: $PRIMARY_MAC)"

# Rewrite netplan config to use NetworkManager as renderer
cat > /etc/netplan/50-cloud-init.yaml << NETPLAN
network:
    renderer: NetworkManager
    ethernets:
        ${PRIMARY_IFACE}:
            dhcp4: true
            dhcp6: true
            match:
                macaddress: '${PRIMARY_MAC}'
            set-name: ${PRIMARY_IFACE}
    version: 2
NETPLAN

# Apply netplan changes (hands interface from systemd-networkd to NM)
netplan generate 2>/dev/null || true
netplan apply 2>/dev/null || true
sleep 5

# Verify NM reports connected
NM_STATE=$(nmcli general status 2>/dev/null | tail -1 | awk '{print $1}')
echo "NetworkManager state: $NM_STATE"
if [ "$NM_STATE" != "connected" ]; then
    echo "WARNING: NM not connected after netplan apply, retrying..."
    systemctl restart NetworkManager 2>/dev/null || true
    sleep 5
    nmcli general status 2>/dev/null || true
fi

# ── 2. Pre-create QGC config to suppress first-run dialogs ──────────────
echo "--- Configuring QGroundControl settings ---"

# QGC v5.0 stores settings at ~/.config/QGroundControl/QGroundControl.ini
QGC_CONFIG_DIR="/home/ga/.config/QGroundControl"
mkdir -p "$QGC_CONFIG_DIR"

cat > "$QGC_CONFIG_DIR/QGroundControl.ini" << 'EOF'
[General]
PromptFlightDataSave=false
PromptFlightDataSaveNotArmed=false
ShowLargeCompass=false
FirstRunPromptComplete=true
FirstRunPromptsVersion=1

[LinkManager]
AutoconnectUDP=true
AutoconnectPixhawk=false
AutoconnectNKE=false
AutoconnectRTKGPS=false
AutoconnectLibrePilot=false
AutoconnectSiKRadio=false
AutoconnectZeroConf=false

[FlightMap]
MapType=4
MapProvider=Bing

[SetupView]
FirstRun=false

[MainWindowState]
visibility=5
x=0
y=0
width=1920
height=1048

[FlyView]
UsePreflightChecklist=true
MapCenteredOnVehicle=true
VirtualJoystick=true
ShowAdditionalIndicatorsCompass=true
ShowSimpleCameraControl=true

[FlyView_InstrumentPanel]
ShowAdditionalIndicatorsCompass=true
EOF

chown -R ga:ga "$QGC_CONFIG_DIR"
echo "QGC config created at $QGC_CONFIG_DIR"

# ── 3. Start ArduPilot SITL in background ───────────────────────────────
echo "--- Starting ArduPilot SITL ---"

ARDUPILOT_DIR="/opt/ardupilot"

# Ensure SITL binary exists
if [ ! -f "$ARDUPILOT_DIR/build/sitl/bin/arducopter" ]; then
    echo "ERROR: ArduCopter SITL binary not found. Attempting to build..."
    su - ga -c "cd $ARDUPILOT_DIR && python3 ./waf configure --board sitl && python3 ./waf copter" || {
        echo "FATAL: Could not build ArduCopter SITL"
        exit 1
    }
fi

# Create a SITL launch script for the ga user
cat > /home/ga/start_sitl.sh << 'SITLSCRIPT'
#!/bin/bash
export PATH="/opt/ardupilot/Tools/autotest:$HOME/.local/bin:$PATH"
cd /opt/ardupilot/ArduCopter

# Start SITL with MAVLink output to UDP 14550 (QGC auto-discovery port)
# and a TCP server on port 5762 for pymavlink scripting connections
setsid python3 /opt/ardupilot/Tools/autotest/sim_vehicle.py \
    --no-mavproxy \
    --vehicle ArduCopter \
    -A "--serial0=udpclient:127.0.0.1:14550 --serial1=tcp:5762" \
    > /tmp/ardupilot_sitl.log 2>&1 &

echo $! > /tmp/sitl_launcher.pid
SITLSCRIPT
chmod +x /home/ga/start_sitl.sh
chown ga:ga /home/ga/start_sitl.sh

su - ga -c "bash /home/ga/start_sitl.sh"

# Poll for SITL to be ready (look for the arducopter process)
echo "--- Waiting for SITL to start ---"
SITL_TIMEOUT=120
SITL_ELAPSED=0
while [ $SITL_ELAPSED -lt $SITL_TIMEOUT ]; do
    if pgrep -f "/opt/ardupilot/build/sitl/bin/arducopter" > /dev/null 2>&1; then
        echo "ArduPilot SITL is running (after ${SITL_ELAPSED}s)"
        break
    fi
    sleep 3
    SITL_ELAPSED=$((SITL_ELAPSED + 3))
done

if ! pgrep -f "/opt/ardupilot/build/sitl/bin/arducopter" > /dev/null 2>&1; then
    echo "WARNING: SITL may not have started properly"
    echo "--- SITL log tail ---"
    tail -30 /tmp/ardupilot_sitl.log 2>/dev/null || true
fi

# Give SITL time to initialize MAVLink and generate heartbeats
sleep 10
echo "SITL should now be sending MAVLink on UDP 14550"

# ── 4. Launch QGroundControl (warm-up launch to clear first-run state) ──
echo "--- Launching QGroundControl (warm-up) ---"

cat > /home/ga/start_qgc.sh << 'QGCSCRIPT'
#!/bin/bash
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export XAUTHORITY=/home/ga/.Xauthority

setsid /opt/QGroundControl-x86_64.AppImage --appimage-extract-and-run \
    > /tmp/qgc.log 2>&1 &

echo $! > /tmp/qgc.pid
QGCSCRIPT
chmod +x /home/ga/start_qgc.sh
chown ga:ga /home/ga/start_qgc.sh

su - ga -c "bash /home/ga/start_qgc.sh"

# Poll for QGC window to appear
echo "--- Waiting for QGC window ---"
QGC_TIMEOUT=60
QGC_ELAPSED=0
while [ $QGC_ELAPSED -lt $QGC_TIMEOUT ]; do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "QGroundControl" 2>/dev/null | head -1 | grep -q .; then
        echo "QGroundControl window detected (after ${QGC_ELAPSED}s)"
        break
    fi
    sleep 3
    QGC_ELAPSED=$((QGC_ELAPSED + 3))
done

if ! DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "QGroundControl" 2>/dev/null | head -1 | grep -q .; then
    echo "WARNING: QGC window not detected, checking processes..."
    ps aux | grep -i qground || true
    echo "--- QGC log tail ---"
    tail -30 /tmp/qgc.log 2>/dev/null || true
fi

# ── 5. Maximize and focus QGC window ────────────────────────────────────
echo "--- Maximizing QGC window ---"
sleep 3

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "QGroundControl" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "QGroundControl" 2>/dev/null || true
sleep 2

# ── 6. Dismiss first-run dialogs via xdotool ────────────────────────────
# QGC v5 shows multiple dialogs on first run:
# 1. Serial permissions warning (Ok button)
# 2. Measurement Units dialog (Ok button)
# 3. Vehicle Information dialog (Ok button)
# Strategy: wait for each dialog, find and click its Ok button
echo "--- Dismissing first-run dialogs ---"

dismiss_dialog_ok() {
    # QGC v5 first-run dialogs have Ok buttons at these 1920x1080 positions
    # (verified via visual grounding on maximized 1920x1080 window):
    # Dialog 1 (Serial permissions): Ok at (1262, 459)
    # Dialog 2 (Measurement Units): Ok at (1065, 383)
    # Dialog 3 (Vehicle Info): Ok at (1031, 444)
    # NOTE: Do NOT use Escape key - it triggers the "Close QGroundControl" dialog
    local attempts=0
    while [ $attempts -lt 5 ]; do
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1262 459 click 1 2>/dev/null || true
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1065 383 click 1 2>/dev/null || true
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1031 444 click 1 2>/dev/null || true
        sleep 1
        attempts=$((attempts + 1))
    done
}

dismiss_dialog_ok
sleep 2

# ── 7. Verify state ─────────────────────────────────────────────────────
echo "--- Verifying environment state ---"
echo "Processes:"
ps aux | grep -E "(arducopter|AppImage)" | grep -v grep || true

echo ""
echo "Open windows:"
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null || true

echo "=== QGroundControl + ArduPilot SITL setup complete ==="
