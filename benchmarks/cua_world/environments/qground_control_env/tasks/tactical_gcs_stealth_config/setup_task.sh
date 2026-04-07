#!/bin/bash
echo "=== Setting up tactical_gcs_stealth_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write SOP
cat > /home/ga/Documents/QGC/tactical_sop.txt << 'SOPDOC'
TACTICAL STANDARD OPERATING PROCEDURE (SOP)
Unit: 4th Reconnaissance Detachment
Operation: Operation Silent Watch
Date: 2026-03-10

1. SYSTEM THEME & VISIBILITY
Operations will occur in bright daylight conditions.
Requirement: Set the QGroundControl UI Color Scheme to "Outdoor" (Light mode) to ensure screen visibility under direct sunlight.

2. NOISE DISCIPLINE (CRITICAL)
Total acoustic emission control (EMCON) is in effect.
Requirement: Mute all QGroundControl audio output. No voice alerts or telemetry sounds are permitted.

3. SATELLITE IMAGERY
Bing maps lack sufficient high-resolution coverage in the operational sector.
Requirement: Change the Flight Map Provider from Bing to "Esri".

4. TACTICAL VIDEO RELAY
We are receiving the primary ISR feed from a high-altitude asset via an encrypted relay.
Requirement: Configure the Video Source to "RTSP Video Stream".
Requirement: Set the RTSP URL exactly to: rtsp://10.0.5.50:8554/tactical_feed

5. POST-CONFIGURATION
Once all settings are applied, you MUST close the QGroundControl application cleanly to flush the preferences to disk. Do not leave the application running after configuration is complete.
SOPDOC

chown ga:ga /home/ga/Documents/QGC/tactical_sop.txt

# 3. Force default QGC settings
echo "--- Resetting QGC config ---"
# Kill QGC if running
pkill -f "AppImage" 2>/dev/null || true
pkill -f "QGroundControl" 2>/dev/null || true
sleep 2

QGC_CONFIG_DIR="/home/ga/.config/QGroundControl"
mkdir -p "$QGC_CONFIG_DIR"

# Overwrite with clean defaults to ensure a known starting state
cat > "$QGC_CONFIG_DIR/QGroundControl.ini" << 'EOF'
[General]
PromptFlightDataSave=false
PromptFlightDataSaveNotArmed=false
ShowLargeCompass=false
FirstRunPromptComplete=true
FirstRunPromptsVersion=1
qgcTheme=0
muteAudio=false

[FlightMap]
MapType=4
MapProvider=Bing

[Video]
VideoSource=
rtspUrl=

[MainWindowState]
visibility=5
x=0
y=0
width=1920
height=1048
EOF
chown -R ga:ga "$QGC_CONFIG_DIR"

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Ensure SITL running (QGC auto-connects)
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 6. Start QGC from scratch
echo "--- Starting QGroundControl ---"
su - ga -c "bash /home/ga/start_qgc.sh"
# Wait for it
QGC_TIMEOUT=30
QGC_ELAPSED=0
while [ $QGC_ELAPSED -lt $QGC_TIMEOUT ]; do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l | grep -qi "QGroundControl"; then
        break
    fi
    sleep 2
    QGC_ELAPSED=$((QGC_ELAPSED + 2))
done

# Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== tactical_gcs_stealth_config task setup complete ==="