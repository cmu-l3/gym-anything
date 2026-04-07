#!/bin/bash
set -e
echo "=== Setting up TCP Link Configuration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure QGC config directory exists
QGC_CONFIG_DIR="/home/ga/.config/QGroundControl"
mkdir -p "$QGC_CONFIG_DIR"
chown -R ga:ga "$QGC_CONFIG_DIR"

QGC_INI="$QGC_CONFIG_DIR/QGroundControl.ini"

# Ensure QGC is NOT running while we modify its INI file
pkill -9 -f "QGroundControl" || true
sleep 1

# Ensure AutoconnectUDP is explicitly TRUE in the config (baseline for verification)
if [ -f "$QGC_INI" ]; then
    if grep -q "AutoconnectUDP" "$QGC_INI"; then
        sed -i 's/AutoconnectUDP=.*/AutoconnectUDP=true/' "$QGC_INI"
    else
        sed -i '/\[LinkManager\]/a AutoconnectUDP=true' "$QGC_INI"
    fi
else
    cat > "$QGC_INI" << 'EOF'
[General]
FirstRunPromptComplete=true

[LinkManager]
AutoconnectUDP=true
EOF
fi

chown ga:ga "$QGC_INI"

# Save baseline config for comparison
cp "$QGC_INI" /tmp/qgc_baseline.ini 2>/dev/null || true

# Create the configuration brief document
TASK_DIR="/home/ga/Documents/QGC"
mkdir -p "$TASK_DIR"

cat > "$TASK_DIR/link_config_brief.txt" << 'BRIEF'
============================================================
    DRONE OPERATIONS DIRECTIVE — COMM LINK MIGRATION
    Greenfield Farming Cooperative
    Issued: 2024-11-15
    Priority: MANDATORY before next flight operations
============================================================

TO:      All Ground Control Station Operators
FROM:    Maria Vasquez, Drone Operations Manager
RE:      Migration from UDP broadcast to dedicated TCP links

BACKGROUND:
-----------
On 2024-11-12, we experienced a critical incident where GCS-2
(barn office B) inadvertently sent a RTL command to Drone #4
which was being actively controlled by GCS-1 (barn office A)
during a spray run over the north wheat field. This occurred
because all stations use UDP broadcast autoconnect, meaning
any GCS can command any vehicle on the network.

Effective immediately, ALL ground control stations must:
1. Configure dedicated TCP communication links
2. Disable UDP autoconnect

CONFIGURATION PARAMETERS:
-------------------------
Each GCS will connect to its assigned drone via the cellular
relay module's TCP endpoint.

For YOUR station (GCS-3, barn office C), configure:

    Link Name:     LTE_Field_Relay
    Protocol:      TCP (client mode, NOT TCP Server)
    Host Address:  127.0.0.1
    Port Number:   5762

PROCEDURE:
----------
1. Open QGroundControl Application Settings -> Comm Links
2. Add new link with above parameters
3. Connect through the new TCP link
4. Verify vehicle telemetry is flowing
5. ONLY AFTER TCP is confirmed working: disable UDP autoconnect
6. Verify vehicle remains connected via TCP only

DOCUMENTATION REQUIREMENT:
--------------------------
After completing the configuration, write a connection
verification report to:

    /home/ga/Documents/QGC/connection_report.txt

The report must include:
  - Link name and connection type
  - Host address and port number
  - Connected vehicle type and status
  - Confirmation that UDP autoconnect is disabled
  - Your sign-off as the configuring technician

SAFETY NOTE:
------------
Do NOT disable UDP autoconnect before the TCP link is
connected and verified. Loss of all communication links
during a flight operation is a Class-A safety incident.

============================================================
END OF DIRECTIVE
============================================================
BRIEF

chown -R ga:ga "$TASK_DIR"

# Remove any pre-existing report
rm -f "$TASK_DIR/connection_report.txt"

# Ensure SITL is running (with TCP server on 5762)
ensure_sitl_running

# Verify TCP port 5762 is available
echo "--- Checking SITL TCP port ---"
for i in {1..20}; do
    if ss -tlnp | grep -q ":5762"; then
        echo "TCP port 5762 is listening"
        break
    fi
    sleep 2
done

if ! ss -tlnp | grep -q ":5762"; then
    echo "WARNING: TCP port 5762 not detected"
    ss -tlnp | grep -i ardu || true
fi

# Ensure QGC is running
ensure_qgc_running
sleep 3

# Maximize and focus QGC
maximize_qgc
sleep 2

# Dismiss any dialogs
dismiss_dialogs
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== TCP Link Configuration task setup complete ==="
echo "Config brief: $TASK_DIR/link_config_brief.txt"
echo "Expected report: $TASK_DIR/connection_report.txt"
echo "SITL TCP port: 5762"
echo "Baseline AutoconnectUDP: true"