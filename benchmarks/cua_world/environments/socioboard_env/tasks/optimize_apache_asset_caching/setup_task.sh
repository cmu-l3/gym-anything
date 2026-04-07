#!/bin/bash
echo "=== Setting up optimize_apache_asset_caching task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Apache is running and Socioboard is accessible
if ! wait_for_http "http://localhost/" 60; then
  echo "ERROR: Socioboard not reachable at http://localhost/"
  exit 1
fi

echo "Forcing a clean state: Disabling caching modules to ensure agent must enable them..."
sudo a2dismod expires headers 2>/dev/null || true
sudo systemctl restart apache2
sleep 2

# Verify clean state
echo "Initial Apache modules:"
apache2ctl -M | grep -E "expires|headers" || echo "(none active - clean state confirmed)"

# Launch Firefox to show the agent the site they are optimizing
echo "Launching Firefox..."
open_socioboard_page "http://localhost/"
sleep 3

# Take an initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Task setup complete ==="