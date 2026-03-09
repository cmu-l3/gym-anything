#!/bin/bash
set -e
echo "=== Setting up identify_software_version task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/software_inventory.txt 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Extract Ground Truth Version (Hidden from agent)
# Find the main executable
LOBBYTRACK_EXE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" -not -path "*/temp/*" 2>/dev/null | head -1)

GT_VERSION="unknown"
if [ -n "$LOBBYTRACK_EXE" ]; then
    echo "Found executable: $LOBBYTRACK_EXE"
    # Try to extract version using strings (looking for X.Y.Z.W pattern common in AssemblyInfo)
    # This captures strings like "6.7.0.0" or "6.0.0.0"
    VERSION_STR=$(strings "$LOBBYTRACK_EXE" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | head -1)
    
    if [ -z "$VERSION_STR" ]; then
        # Fallback to shorter version strings if long one not found
        VERSION_STR=$(strings "$LOBBYTRACK_EXE" | grep -E "^Version [0-9]+\.[0-9]+" | head -1 | sed 's/Version //')
    fi
    
    if [ -n "$VERSION_STR" ]; then
        GT_VERSION="$VERSION_STR"
    fi
fi

# Save ground truth to a hidden file for export_result.sh to pick up
echo "$GT_VERSION" > /tmp/ground_truth_version.txt
echo "Free" > /tmp/ground_truth_edition.txt # Based on the installer used in env setup

echo "Ground Truth - Version: $GT_VERSION"

# 4. Ensure Lobby Track is running
ensure_lobbytrack_running

# 5. Wait for window and maximize
sleep 5
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "lobby\|jolly\|visitor\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="