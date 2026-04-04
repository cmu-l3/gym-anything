#!/bin/bash
# Setup script for Headless CLI Crawl Automation task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Headless CLI Crawl Task ==="

# 1. Kill any running instances to ensure headless mode doesn't conflict
kill_screamingfrog ga
sleep 1

# 2. Record task start timestamp for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 3. clean up previous results to ensure fresh run
OUTPUT_DIR="/home/ga/Documents/SEO/cli_results"
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning up previous output directory..."
    rm -rf "$OUTPUT_DIR"
fi

# 4. Verify CLI tool is available
if ! command -v screamingfrogseospider &> /dev/null; then
    echo "WARNING: screamingfrogseospider not found in PATH."
    # Try to verify alternate paths just in case
    if [ -x "/opt/ScreamingFrogSEOSpider/ScreamingFrogSEOSpider" ]; then
        echo "Found binary at /opt/ScreamingFrogSEOSpider/ScreamingFrogSEOSpider"
        # Ensure symlink exists
        if [ ! -L "/usr/bin/screamingfrogseospider" ]; then
             ln -s /opt/ScreamingFrogSEOSpider/ScreamingFrogSEOSpider /usr/bin/screamingfrogseospider
        fi
    fi
fi

# 5. Open a terminal for the agent
# (Standard env usually starts with terminal, but we ensure one is focused)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 2
fi

# Focus terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "  1. Run 'screamingfrogseospider' with appropriate flags"
echo "  2. Target: https://quotes.toscrape.com/"
echo "  3. Output: ~/Documents/SEO/cli_results/"
echo "  4. Export: Internal:All"