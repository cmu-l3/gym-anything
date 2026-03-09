#!/bin/bash
set -e

echo "=== Setting up Pin Participant task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Jitsi is healthy
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# 2. Cleanup previous sessions
pkill -f firefox || true
pkill -f epiphany || true
rm -f /tmp/task_result.json 2>/dev/null || true
sleep 2

# 3. Start Firefox (Agent)
echo "Starting Firefox (Agent)..."
# Using the restart_firefox helper which handles nohup/display
restart_firefox "http://localhost:8080/AnnualTownHall" 10
maximize_firefox
focus_firefox

# Join the meeting (click Join button if on pre-join screen)
# This helper waits, clicks center/input, then Enter
join_meeting 10

# 4. Start Epiphany (Guest: Keynote Speaker)
echo "Starting Epiphany (Keynote Speaker)..."
# Guest URL with params to set name and mute audio/video to prevent feedback loops
# We assume the 'Keynote Speaker' has their camera ON (simulated by not passing config.startWithVideoMuted=true, 
# or letting it be default, but for stability in docker we often mute. 
# However, to pin a VIDEO, it's better if they have video. 
# Since we don't have a real webcam pass-through easily for the guest, they will show as a grey avatar/tile.
# Pinning works on the tile regardless of video state.
GUEST_URL="http://localhost:8080/AnnualTownHall#userInfo.displayName=%22Keynote%20Speaker%22&config.startWithAudioMuted=true"

# Epiphany doesn't support the same flags as Chrome, so we just launch it.
DISPLAY=:1 nohup epiphany-browser "$GUEST_URL" >/tmp/epiphany_guest.log 2>&1 &

# Wait for guest to join
sleep 15

# 5. Arrange Windows
# Minimize Epiphany so it doesn't obscure Firefox (agent needs to see Firefox)
# We can't easily minimize specific windows with wmctrl if they share class, but they are different browsers.
DISPLAY=:1 wmctrl -r "Epiphany" -b add,hidden 2>/dev/null || true

# Bring Firefox to front and ensure maximized
maximize_firefox
focus_firefox

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Meeting Room: AnnualTownHall"
echo "Target: Keynote Speaker"