#!/bin/bash
# Setup script for Site Architecture Visualization task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Site Architecture Visualization Task ==="

# 1. Kill any existing instances to ensure clean state
kill_screamingfrog ga
sleep 1

# 2. Clear previous crawl data and configuration
# This ensures the agent must set the limit themselves and crawl from scratch
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/spider.config 2>/dev/null || true # Reset config to force manual limit setting
    echo "Cleared Screaming Frog cache and config"
fi

# 3. Restore default config but keep essential system settings if needed
# We want the agent to set the limit, so we won't pre-set it in a config file here.
# The default install script sets up a basic spider.config, we can let that be or ensure it doesn't have a limit.

# 4. Prepare export directory
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
# Remove any existing site graph files to prevent false positives
rm -f "$EXPORT_DIR"/site_graph.html 2>/dev/null || true
rm -f "$EXPORT_DIR"/*.html 2>/dev/null || true

# 5. Record task start timestamp for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 6. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 7. Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# 8. Wait for window
if ! wait_for_window "Screaming Frog\|SEO Spider" 60; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

# 9. Handle potential EULA
sleep 5
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# 10. Wait for app ready state
echo "Waiting for Screaming Frog to initialize..."
wait_for_sf_ready 60

# 11. Focus main window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 12. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: https://books.toscrape.com/"
echo "Instructions:"
echo "1. Set Crawl Limit to 200 (Config > Spider > Limits)"
echo "2. Crawl site"
echo "3. Generate Force-Directed Crawl Diagram (Visualisations menu)"
echo "4. Save as ~/Documents/SEO/exports/site_graph.html"