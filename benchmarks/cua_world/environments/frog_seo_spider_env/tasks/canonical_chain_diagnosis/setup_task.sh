#!/bin/bash
# Setup script for Canonical Chain Diagnosis task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Canonical Chain Diagnosis Task ==="

# 1. Kill existing instances to ensure fresh state
kill_screamingfrog ga
sleep 1

# 2. Clear previous crawl data (CRITICAL for valid analysis testing)
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# 3. Prepare output directories
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$REPORTS_DIR"
# Clear specific target files if they exist
rm -f "$REPORTS_DIR/canonical_chains_audit.csv" 2>/dev/null || true
rm -f "$REPORTS_DIR/chain_summary.txt" 2>/dev/null || true

# 4. Record task start time for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 5. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# 6. Handle EULA if it appears
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# 7. Wait for app initialization
wait_for_sf_ready 60

# 8. Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 9. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: https://crawler-test.com/"
echo "Required Output: ~/Documents/SEO/reports/canonical_chains_audit.csv"
echo "Required Output: ~/Documents/SEO/reports/chain_summary.txt"