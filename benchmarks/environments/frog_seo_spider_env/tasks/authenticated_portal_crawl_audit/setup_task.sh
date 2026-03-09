#!/bin/bash
# Setup script for Authenticated Portal Crawl Audit
# Ensures clean state and prepares directories

source /workspace/scripts/task_utils.sh

echo "=== Setting up Authenticated Portal Crawl Audit ==="

# Kill any running Screaming Frog instances
kill_screamingfrog ga
sleep 1

# Record task start time for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# Clear previous crawl data to ensure a fresh session
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    echo "Clearing Screaming Frog cache..."
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# Prepare export and report directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/

# Remove any existing exports to prevent confusion
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/*.txt 2>/dev/null || true

# Record initial file count (should be 0)
ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l > /tmp/initial_export_count

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window not detected yet"
fi

# Handle EULA if it appears
sleep 5
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "Accepting EULA..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window key Return" || true
    sleep 3
fi

# Wait for full initialization
echo "Waiting for application ready state..."
wait_for_sf_ready 60

# Focus main window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Credentials to use:"
echo "  URL: http://quotes.toscrape.com/login"
echo "  User: admin"
echo "  Pass: password"