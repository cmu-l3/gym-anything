#!/bin/bash
# Setup script for Hreflang Validation Audit task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Hreflang Validation Audit Task ==="

# Kill any existing Screaming Frog instances to ensure clean state
kill_screamingfrog ga
sleep 1

# Record task start time for anti-gaming (file modification checks)
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# CRITICAL: Clear previous crawl data
# This prevents the agent from exporting old cached data
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
    echo "Cleared Screaming Frog cache"
fi

# Create required directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Clear any existing files in export/report directories to avoid confusion
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/*.txt 2>/dev/null || true

# Record initial export count (should be 0)
echo "0" > /tmp/initial_export_count

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process to start
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for main window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# Handle EULA dialog if present (common first-run issue)
echo "Checking for EULA dialog..."
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for SF to fully initialize (loading screen to finish)
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60
echo "[$(date -Iseconds)] wait_for_sf_ready completed" >> /tmp/setup_timing.log

# Additional stabilization
sleep 5

# Focus Screaming Frog window to ensure it's ready for input
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

# Take setup screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Hreflang Validation Audit Setup Complete ==="
echo ""
echo "TASK INSTRUCTIONS:"
echo "1. Crawl https://crawler-test.com/"
echo "2. Analyze Hreflang data in the 'Hreflang' tab"
echo "3. Export 'Hreflang' data to CSV in ~/Documents/SEO/exports/ (name must contain 'hreflang')"
echo "4. Export 'Internal > HTML' data to CSV in ~/Documents/SEO/exports/ (name must contain 'internal')"
echo "5. Write a validation report to ~/Documents/SEO/reports/hreflang_report.txt"