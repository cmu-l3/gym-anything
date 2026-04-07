#!/bin/bash
# setup_task.sh - Pre-task hook for PWA Workspace Provisioning
# Cleans up existing PWA shortcuts and ensures Edge is ready.

set -e

echo "=== Setting up PWA Workspace Provisioning task ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill any existing Edge instances
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 2. Cleanup existing PWA desktop entries to ensure fresh install
echo "Cleaning up existing PWA desktop entries..."
# Standard location for Chrome/Edge PWAs on Linux
APPS_DIR="/home/ga/.local/share/applications"
DESKTOP_DIR="/home/ga/Desktop"

# Remove entries related to target apps
for pattern in "*photopea*" "*excalidraw*" "*devdocs*"; do
    find "$APPS_DIR" -name "$pattern" -delete 2>/dev/null || true
    find "$DESKTOP_DIR" -name "$pattern" -delete 2>/dev/null || true
done

# Also clean up Edge's Web Applications directory to remove internal state
WEB_APPS_DIR="/home/ga/.config/microsoft-edge/Default/Web Applications"
if [ -d "$WEB_APPS_DIR" ]; then
    rm -rf "$WEB_APPS_DIR"/*
fi

# 3. Record task start timestamp
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch Microsoft Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# Wait for Edge to start
echo "Waiting for Edge window..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window appeared."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Maximize the window
sleep 2
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="