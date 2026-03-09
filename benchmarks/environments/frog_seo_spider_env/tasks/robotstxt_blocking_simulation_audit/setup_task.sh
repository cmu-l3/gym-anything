#!/bin/bash
# Setup script for Robots.txt Blocking Simulation task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Robots.txt Blocking Simulation Task ==="

# Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# Record task start time
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# Clear previous crawl data to ensure fresh start state
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/spider.config 2>/dev/null || true # Reset config so custom robots isn't pre-set
    echo "Cleared Screaming Frog cache"
fi

# Restore default config (ensure we don't start with weird settings)
# We want the agent to do the configuration
if [ -f "/workspace/config/spider.config.default" ]; then
    cp "/workspace/config/spider.config.default" "$SF_DATA_DIR/spider.config"
fi

# Clean export directory
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process to start
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for main window
if ! wait_for_window "Screaming Frog\|SEO Spider" 60; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

# Wait for SF to fully initialize
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

# Focus Screaming Frog window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Configure Custom Robots.txt to block '/catalogue/category/books/travel_2/'"
echo "2. Crawl 'https://books.toscrape.com/'"
echo "3. Export blocked URLs to ~/Documents/SEO/exports/blocked_urls.csv"
echo "4. Export allowed URLs to ~/Documents/SEO/exports/allowed_pages.csv"