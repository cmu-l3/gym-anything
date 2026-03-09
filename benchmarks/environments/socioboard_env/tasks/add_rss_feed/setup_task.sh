#!/bin/bash
echo "=== Setting up add_rss_feed task ==="

source /workspace/scripts/task_utils.sh

# Remove any root-owned tmp files from previous runs that would block writes
sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png /tmp/rss_log_baseline 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Wait for Socioboard to be ready
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable at http://localhost/"
  exit 1
fi

# Clear any existing session by navigating to logout first
log "Clearing browser session via logout..."
open_socioboard_page "http://localhost/logout"
sleep 2

# Open Socioboard login page (agent will see login form)
navigate_to "http://localhost/login"
sleep 3

# Record Apache access log baseline (line count before agent interaction)
# Verifier uses this to detect POST /getRss requests made by the agent
sudo wc -l /var/log/apache2/socioboard_access.log 2>/dev/null | awk '{print $1}' > /tmp/rss_log_baseline || echo "0" > /tmp/rss_log_baseline
log "Apache log baseline: $(cat /tmp/rss_log_baseline) lines"

take_screenshot /tmp/task_start.png
log "Task start screenshot saved: /tmp/task_start.png"
echo "=== Task setup complete: add_rss_feed ==="
