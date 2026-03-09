#!/bin/bash
# Setup script for Broken Image Asset Audit
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Broken Image Asset Audit Task ==="

# 1. Cleanup Environment
# Kill any running instances to ensure a fresh start
kill_screamingfrog ga
sleep 1

# Clear previous crawl data (cache/db) to prevent finding cached results
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    echo "Clearing Screaming Frog cache..."
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# Clear exports directory to ensure we identify the NEW file
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/*broken_images*.csv 2>/dev/null || true
# Clean up other potential exports to make verification cleaner, 
# but preserve unrelated files if possible (though for a task env, cleaning is safer)
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true

# 2. Record Initial State
# Timestamp for anti-gaming (verification checks file mtime > task_start)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# 3. Launch Application
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for window
if ! wait_for_window "Screaming Frog\|SEO Spider" 60; then
    echo "WARNING: Window detection timed out, but proceeding..."
fi

# Wait for full initialization (loading screen -> main UI)
echo "Waiting for application initialization..."
wait_for_sf_ready 60

# 4. Handle First-Run Dialogs (EULA)
# Note: install script handles some, but double check
eula_window=$(DISPLAY=:1 wmctrl -l | grep -i "License Agreement" | awk '{print $1}' || echo "")
if [ -n "$eula_window" ]; then
    echo "Accepting EULA..."
    DISPLAY=:1 xdotool windowactivate --sync "$eula_window"
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 2
fi

# 5. Final Prep
# Focus the main window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize for better VLM visibility
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="