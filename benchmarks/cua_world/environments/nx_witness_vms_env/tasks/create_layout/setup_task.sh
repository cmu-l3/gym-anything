#!/bin/bash
echo "=== Setting up create_layout task ==="

source /workspace/scripts/task_utils.sh

# Refresh auth token
refresh_nx_token > /dev/null 2>&1 || true

# Record initial layout count for baseline
INITIAL_COUNT=$(count_layouts 2>/dev/null || echo "0")
echo "Initial layout count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/nx_initial_layout_count.txt

# Delete 'Security Overview' layout if it already exists (idempotent setup)
EXISTING_LAYOUT=$(get_layout_by_name "Security Overview" 2>/dev/null || true)
if [ -n "$EXISTING_LAYOUT" ] && [ "$EXISTING_LAYOUT" != "null" ]; then
    EXISTING_ID=$(echo "$EXISTING_LAYOUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
    if [ -n "$EXISTING_ID" ]; then
        echo "Removing existing 'Security Overview' layout (id: $EXISTING_ID)"
        nx_api_delete "/rest/v1/layouts/${EXISTING_ID}" || true
        sleep 2
    fi
fi

# Kill any existing Nx Witness client instances
pkill -f "applauncher" 2>/dev/null || true
pkill -f "client.*networkoptix" 2>/dev/null || true
pkill -f "nxwitness" 2>/dev/null || true
sleep 3

# Pre-configure keyring to avoid dialogs: set up an unencrypted keyring
mkdir -p /home/ga/.local/share/keyrings 2>/dev/null || true
# Create an empty default keyring that won't prompt for password
if [ ! -f /home/ga/.local/share/keyrings/login.keyring ] && [ ! -f /home/ga/.local/share/keyrings/default.keyring ]; then
    python3 -c "
import os, struct
# Create a minimal GnomeKeyring-compatible file (empty keyring, no password)
# This avoids the 'Choose password for new keyring' dialog
" 2>/dev/null || true
fi

# Find and launch the Nx Witness desktop client
APPLAUNCHER=""
for path in \
    /opt/networkoptix/client/*/bin/applauncher \
    /opt/networkoptix-client/*/bin/applauncher \
    /opt/networkoptix*/client/*/bin/applauncher; do
    if [ -f "$path" ]; then
        APPLAUNCHER="$path"
        break
    fi
done

if [ -z "$APPLAUNCHER" ]; then
    APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)
fi

if [ -n "$APPLAUNCHER" ]; then
    echo "Launching Nx Witness desktop client: $APPLAUNCHER"
    DISPLAY=:1 "$APPLAUNCHER" &
    CLIENT_PID=$!
    echo "Client PID: $CLIENT_PID"

    # Wait for client to initialize
    sleep 8

    # Dismiss keyring dialog 1 — "Choose password for new keyring"
    # Click Continue at VG(707, 452) → actual(1060, 678)
    DISPLAY=:1 xdotool mousemove 1060 678 click 1 2>/dev/null || true
    sleep 2

    # Dismiss keyring dialog 2 — "Store passwords unencrypted?"
    # Click Continue at VG(707, 419) → actual(1060, 628)
    DISPLAY=:1 xdotool mousemove 1060 628 click 1 2>/dev/null || true
    sleep 3

    # Dismiss EULA dialog — "I Agree" at VG(885, 522) → actual(1327, 783)
    DISPLAY=:1 xdotool mousemove 1327 783 click 1 2>/dev/null || true
    sleep 5

    # Bring the desktop client to the foreground and maximize
    NX_WIN=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Nx Witness Client\|Nx Witness\|NxWitness" | head -1 | awk '{print $1}')
    if [ -n "$NX_WIN" ]; then
        DISPLAY=:1 wmctrl -ia "$NX_WIN" 2>/dev/null || true
        DISPLAY=:1 wmctrl -ir "$NX_WIN" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    else
        DISPLAY=:1 wmctrl -r "Nx Witness Client" -b add,maximized_vert,maximized_horz 2>/dev/null || \
        DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    sleep 2

    echo "Desktop client launched, dialogs dismissed, and window focused"
else
    echo "Warning: Nx Witness desktop client not found"
fi

# Take initial screenshot
take_screenshot /tmp/nx_create_layout_start.png

echo "=== create_layout task setup complete ==="
echo "Task: Create layout 'Security Overview' with all cameras in 2x2 grid"
echo "Server: localhost:7001"
echo "Credentials: admin / Admin1234!"
