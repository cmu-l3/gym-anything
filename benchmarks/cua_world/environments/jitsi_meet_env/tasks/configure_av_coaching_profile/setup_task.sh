#!/bin/bash
set -e
echo "=== Setting up configure_av_coaching_profile task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous artifacts
rm -f /tmp/av_config_final.png \
      /tmp/noise_suppression_evidence.png \
      /tmp/task_initial_state.png \
      /tmp/task_result.json

# 3. Ensure Jitsi is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# 4. Start Firefox and join the specific meeting
# Using 'restart_firefox' from utils which handles cleanup and profile
MEETING_URL="${JITSI_BASE_URL:-http://localhost:8080}/VirtualHIITClass"
echo "Navigating to $MEETING_URL"
restart_firefox "$MEETING_URL" 12

# 5. Maximize window
maximize_firefox
sleep 2

# 6. Join meeting (bypass pre-join screen)
# This helper clicks the name input and presses Enter
join_meeting 15

# 7. Ensure UI is stable and toolbar is visible
DISPLAY=:1 xdotool mousemove 960 540
sleep 2

# 8. Capture initial state screenshot (Evidence of starting state)
# We expect self-view to be VISIBLE and noise suppression OFF by default
take_screenshot /tmp/task_initial_state.png

# 9. Verify setup was successful
if [ ! -f /tmp/task_initial_state.png ]; then
    echo "WARNING: Failed to capture initial state screenshot"
fi

echo "=== Task setup complete ==="