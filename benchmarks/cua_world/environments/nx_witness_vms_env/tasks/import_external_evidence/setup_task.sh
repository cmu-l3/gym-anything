#!/bin/bash
set -e

echo "=== Setting up import_external_evidence task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 2. Prepare Evidence Data
# We use ffmpeg to generate robust "real" video files with distinct characteristics
# to simulate different sources (Phone vs Drone).
EVIDENCE_DIR="/home/ga/Downloads/Evidence"
mkdir -p "$EVIDENCE_DIR"

echo "Generating evidence files..."

# File 1: Bystander Clip (Vertical video aspect ratio, shaky/handheld simulation via noise)
if [ ! -f "$EVIDENCE_DIR/bystander_clip_01.mp4" ]; then
    ffmpeg -f lavfi -i "testsrc=duration=15:size=720x1280:rate=30" \
           -f lavfi -i "sine=frequency=1000:duration=15" \
           -vf "drawtext=text='EVIDENCE - PHONE':fontcolor=white:fontsize=40:x=(w-text_w)/2:y=(h-text_h)/2, noise=alls=20:allf=t+u" \
           -c:v libx264 -pix_fmt yuv420p -c:a aac -y \
           "$EVIDENCE_DIR/bystander_clip_01.mp4" 2>/dev/null
fi

# File 2: Drone Survey Clip (Wide aspect, high frame rate, overlay text)
if [ ! -f "$EVIDENCE_DIR/drone_survey_clip.mp4" ]; then
    ffmpeg -f lavfi -i "testsrc=duration=15:size=1920x1080:rate=60" \
           -vf "drawtext=text='DRONE TELEMETRY - ALT 400':fontcolor=yellow:fontsize=50:x=50:y=50" \
           -c:v libx264 -pix_fmt yuv420p -y \
           "$EVIDENCE_DIR/drone_survey_clip.mp4" 2>/dev/null
fi

chown -R ga:ga "/home/ga/Downloads"
echo "Evidence files prepared in $EVIDENCE_DIR"

# 3. Clean up previous state (Idempotency)
# Authenticate
refresh_nx_token > /dev/null 2>&1 || true

# Check/Delete existing layout "Case #4492-Investigation"
LAYOUT_ID=$(get_layout_by_name "Case #4492-Investigation" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
if [ -n "$LAYOUT_ID" ]; then
    echo "Cleaning up existing layout..."
    nx_api_delete "/rest/v1/layouts/$LAYOUT_ID"
fi

# We can't easily delete local file resources via API as they are client-managed,
# but we can ensure the layout is gone. The agent will have to handle duplicates if they exist,
# which is a realistic annoyance.

# 4. Launch Nx Witness Desktop Client
# We kill existing instances to ensure a clean start
pkill -f "nxwitness" || true
pkill -f "Network Optix" || true
sleep 2

# Find launcher
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)

if [ -n "$APPLAUNCHER" ]; then
    echo "Launching Nx Witness Client..."
    # Launch in background as user ga
    su - ga -c "DISPLAY=:1 \"$APPLAUNCHER\"" &
    
    # Wait for window
    echo "Waiting for client window..."
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
            echo "Nx Witness Client detected."
            break
        fi
        sleep 1
    done
    
    # Maximize
    sleep 5
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Handle Login if necessary (Auto-login usually works if previously configured, 
    # but we ensure the window is focused).
    DISPLAY=:1 wmctrl -a "Nx Witness" 2>/dev/null || true
else
    echo "WARNING: Nx Witness Client not found!"
fi

# 5. Open File Manager (Nautilus) to the evidence folder
# This makes the task smoother for the agent
su - ga -c "DISPLAY=:1 nautilus '$EVIDENCE_DIR' &"
sleep 2
DISPLAY=:1 wmctrl -r "Evidence" -e 0,100,100,800,600 2>/dev/null || true

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="