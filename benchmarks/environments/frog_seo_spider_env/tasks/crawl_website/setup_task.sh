#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Crawl Website Task ==="

# Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# Note: This task uses a real public website (https://crawler-test.com/)
# specifically designed for SEO crawler testing - no local server needed

# Record task start time for file modification tracking
echo "$(date -Iseconds)" > /tmp/task_start_time
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# CRITICAL: Clear any previous crawl data to ensure fresh start state
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    # Clear crawl cache and recent projects
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
    echo "Cleared Screaming Frog cache directory"
fi

# Record initial state - count existing exports
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
INITIAL_EXPORT_COUNT=$(ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l)
echo "$INITIAL_EXPORT_COUNT" > /tmp/initial_export_count

# Clear any previous crawl data/exports from this task
rm -f "$EXPORT_DIR"/internal_all*.csv 2>/dev/null || true
rm -f /tmp/exported_crawl_report.csv 2>/dev/null || true

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for Screaming Frog to start
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for main window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# Handle EULA dialog if it appears (first-run dialog)
echo "Checking for EULA dialog..."
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    # Focus the EULA window and press Enter to accept
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for application to be FULLY ready (not just window visible)
# The app shows a loading screen first, then the main interface
echo "Waiting for Screaming Frog to fully initialize..."
echo "[$(date -Iseconds)] Starting wait_for_sf_ready..." >> /tmp/setup_timing.log
wait_for_sf_ready 60
echo "[$(date -Iseconds)] wait_for_sf_ready completed" >> /tmp/setup_timing.log

# Additional stabilization time after app reports ready
sleep 5
echo "[$(date -Iseconds)] Post-ready stabilization complete" >> /tmp/setup_timing.log

# Click on center of the screen to select desktop, then focus window
echo "Selecting desktop and focusing window..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Screaming Frog window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

sleep 2

echo "=== Crawl Website Task Setup Complete ==="
echo ""
echo "Instructions:"
echo "  1. Screaming Frog SEO Spider should be open"
echo "  2. Enter 'https://crawler-test.com/' in the URL bar at the top"
echo "  3. Click the 'Start' button or press Enter to begin crawling"
echo "  4. Wait for the crawl to complete (URL count will stop increasing)"
echo ""
echo "Target URL: https://crawler-test.com/"
echo "Note: This is a real public website designed for SEO crawler testing"
echo "Expected: The crawler should find 10+ pages on this test website"
