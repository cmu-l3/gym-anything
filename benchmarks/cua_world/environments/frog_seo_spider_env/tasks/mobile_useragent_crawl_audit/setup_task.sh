#!/bin/bash
# Setup script for Mobile User-Agent Crawl Audit

source /workspace/scripts/task_utils.sh

echo "=== Setting up Mobile User-Agent Crawl Audit ==="

# 1. Kill existing instances
kill_screamingfrog ga
sleep 1

# 2. Record Task Start Time
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 3. Clean up previous state
echo "Cleaning up previous data..."
SF_CONFIG_DIR="/home/ga/.ScreamingFrogSEOSpider"
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_DIR="/home/ga/Documents/SEO/reports"

# Create directories
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORT_DIR"
chown -R ga:ga "/home/ga/Documents/SEO"

# Remove previous exports for this task
rm -f "$EXPORT_DIR"/mobile_internal_html.csv 2>/dev/null || true
rm -f "$EXPORT_DIR"/mobile_custom_extraction.csv 2>/dev/null || true
rm -f "$REPORT_DIR"/mobile_readiness_report.txt 2>/dev/null || true

# Reset Spider Configuration to Default (to ensure UA is reset)
# We preserve license if it exists, but reset spider.config
if [ -f "$SF_CONFIG_DIR/spider.config" ]; then
    # Create a clean default config that ensures User-Agent is standard
    # and Custom Extraction is empty
    cat > "$SF_CONFIG_DIR/spider.config" << 'CONFIGEOF'
# Screaming Frog SEO Spider Configuration
checkForUpdates=false
eulaAccepted=true
# Default User Agent
userAgent=Screaming Frog SEO Spider
# Reset Custom Extraction
customExtraction=
CONFIGEOF
    chown ga:ga "$SF_CONFIG_DIR/spider.config"
    echo "Reset spider.config to defaults"
fi

# 4. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 5. Wait for application
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

echo "Waiting for Screaming Frog GUI..."
wait_for_sf_ready 60

# 6. Final UI Setup
sleep 5
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="
echo "Task: Configure Mobile UA, Setup Viewport Extraction, Crawl & Report."
echo "Target: https://books.toscrape.com/"