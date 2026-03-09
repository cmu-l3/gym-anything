#!/bin/bash
# Setup script for Legacy Meta Keywords Cleanup Audit

source /workspace/scripts/task_utils.sh

echo "=== Setting up Legacy Meta Keywords Audit Task ==="

# 1. Kill any existing instances to ensure fresh state
kill_screamingfrog ga
sleep 1

# 2. Clear previous crawl data (prevent checking cached results)
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    echo "Cleared Screaming Frog cache"
fi

# 3. Prepare export directory and remove any previous target file
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "/home/ga/Documents/SEO"
TARGET_FILE="$EXPORT_DIR/meta_keywords_audit.csv"
rm -f "$TARGET_FILE" 2>/dev/null || true

# 4. Record task start timestamp for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 5. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 6. Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# 7. Wait for window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

# 8. Handle EULA if it appears
echo "Checking for EULA..."
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# 9. Wait for full readiness
echo "Waiting for UI to stabilize..."
wait_for_sf_ready 60

# 10. Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 11. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: https://crawler-test.com/"
echo "Goal: Find '<meta name=\"keywords\"' in HTML Source"