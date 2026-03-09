#!/bin/bash
set -e
echo "=== Setting up disable_video_mirroring task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Jitsi is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# 3. Clean start: Stop any existing Firefox instances
stop_firefox

# 4. Clear specific local storage / profile data to ensure default settings
# (We want 'Mirror local video' to be in its default state, usually Enabled)
# The setup_jitsi.sh script creates a clean profile at /home/ga/.mozilla/firefox/jitsi.profile
# We can just let restart_firefox handle the profile loading.

# 5. Start Firefox at the specific meeting URL (Pre-join screen)
ROOM_URL="${JITSI_BASE_URL:-http://localhost:8080}/MathTutoringSession"
echo "Navigating to $ROOM_URL"

# Use restart_firefox from task_utils to handle profile and process management
restart_firefox "$ROOM_URL" 10

# 6. Maximize and focus
maximize_firefox
focus_firefox

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Join 'MathTutoringSession' as 'Tutor Alex' and disable 'Mirror local video' in Settings > Video."