#!/bin/bash
# Setup script for Generate XML Sitemap task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Generate XML Sitemap Task ==="

# Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# Record task start time for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# Clear previous crawl data to ensure fresh start
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    echo "Cleared Screaming Frog cache"
fi

# Create required directories
SITEMAPS_DIR="/home/ga/Documents/SEO/sitemaps"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$SITEMAPS_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# CRITICAL: Remove any existing files to force fresh creation
rm -f "$SITEMAPS_DIR/sitemap.xml" 2>/dev/null || true
rm -f "$REPORTS_DIR/sitemap_summary.txt" 2>/dev/null || true

# Record initial file counts
echo "0" > /tmp/initial_sitemap_count

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
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# Handle EULA dialog if present
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
echo "[$(date -Iseconds)] SF ready" >> /tmp/setup_timing.log

# Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Generate XML Sitemap Setup Complete ==="
echo ""
echo "TASK: Crawl https://books.toscrape.com/ and generate an XML sitemap."
echo "OUTPUTS REQUIRED:"
echo "  1. Sitemap file: ~/Documents/SEO/sitemaps/sitemap.xml"
echo "  2. Summary report: ~/Documents/SEO/reports/sitemap_summary.txt"