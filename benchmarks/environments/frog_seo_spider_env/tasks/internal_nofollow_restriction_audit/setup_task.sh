#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Internal Nofollow Restriction Audit Task ==="

# 1. clean up environment
kill_screamingfrog ga
sleep 1

# Clear previous crawl data (prevent finding old data)
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    echo "Cleared Screaming Frog cache"
fi

# Create export/report directories and clear old files
mkdir -p "/home/ga/Documents/SEO/exports"
mkdir -p "/home/ga/Documents/SEO/reports"
rm -f "/home/ga/Documents/SEO/exports/internal_nofollow_report.csv"
rm -f "/home/ga/Documents/SEO/reports/nofollow_summary.txt"

# Set permissions
chown -R ga:ga "/home/ga/Documents/SEO"

# 2. Record start state
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 3. Launch Application
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Window not detected within timeout"
fi

# Handle EULA if needed
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "Accepting EULA..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window key Return" || true
    sleep 2
fi

# Wait for full initialization
wait_for_sf_ready 60

# Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 4. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: https://crawler-test.com/"
echo "Task: Export Internal Nofollow Outlinks CSV and write summary."