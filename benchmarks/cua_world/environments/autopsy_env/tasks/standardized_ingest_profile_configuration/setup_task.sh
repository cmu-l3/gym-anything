#!/bin/bash
# Setup script for standardized_ingest_profile_configuration task

echo "=== Setting up standardized_ingest_profile_configuration task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/profile_config_result.json /tmp/profile_config_start_time 2>/dev/null || true

# Remove previous case directories
for d in /home/ga/Cases/Backlog_Triage_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Remove any existing Fast_Triage profile to prevent gaming
PROFILE_DIR="/home/ga/.autopsy/dev/config/IngestProfiles/Fast_Triage"
[ -d "$PROFILE_DIR" ] && rm -rf "$PROFILE_DIR" && echo "Removed old profile: $PROFILE_DIR"
[ -d "${PROFILE_DIR}_" ] && rm -rf "${PROFILE_DIR}_"
[ -d "/home/ga/.autopsy/dev/config/IngestProfiles/Fast Triage" ] && rm -rf "/home/ga/.autopsy/dev/config/IngestProfiles/Fast Triage"

# Ensure reports directory exists
mkdir -p /home/ga/Reports
rm -f /home/ga/Reports/profile_audit.txt
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/ntfs_undel.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/profile_config_start_time
echo "Task start time recorded: $(cat /tmp/profile_config_start_time)"

# ── Kill any running Autopsy and Relaunch ─────────────────────────────────────
kill_autopsy
echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching at ${WELCOME_ELAPSED}s..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    kill_autopsy
    sleep 2
    launch_autopsy
    FINAL_ELAPSED=0
    while [ $FINAL_ELAPSED -lt 120 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
            WELCOME_FOUND=true
            break
        fi
        DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
        sleep 5; FINAL_ELAPSED=$((FINAL_ELAPSED + 5))
    done
fi

sleep 3
# Close any lingering popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot showing clean state
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="