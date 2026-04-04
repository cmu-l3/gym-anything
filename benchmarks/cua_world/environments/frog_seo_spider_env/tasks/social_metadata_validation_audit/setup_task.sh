#!/bin/bash
# Setup script for Social Media Metadata Audit task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Social Media Metadata Audit Task ==="

# Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# Record task start time
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# Clear previous crawl data to ensure clean state (force agent to configure extraction)
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
    # We notably do NOT delete spider.config completely to keep license/rendering settings,
    # but we should ensure no previous custom extraction rules linger if stored there.
    # (Screaming Frog usually stores config in spider.config, but clearing recent crawls helps).
    echo "Cleared Screaming Frog cache"
fi

# Create required directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Clear specific target files if they exist
rm -f "$EXPORT_DIR/social_tags_export.csv" 2>/dev/null || true
rm -f "$REPORTS_DIR/missing_social_tags.txt" 2>/dev/null || true

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

# Handle EULA dialog if present
echo "Checking for EULA dialog..."
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for SF to fully initialize
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60
echo "[$(date -Iseconds)] wait_for_sf_ready completed" >> /tmp/setup_timing.log

# Focus Screaming Frog window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Social Metadata Audit Setup Complete ==="
echo ""
echo "TASK INSTRUCTIONS:"
echo "  Target URL: https://crawler-test.com/"
echo "  Goal: Extract 'og:title' and 'og:image' using Custom Extraction."
echo "  1. Configure Custom Extraction (Configuration > Custom > Custom Extraction)."
echo "  2. Crawl the site."
echo "  3. Export results to ~/Documents/SEO/exports/social_tags_export.csv."
echo "  4. Write analysis to ~/Documents/SEO/reports/missing_social_tags.txt."