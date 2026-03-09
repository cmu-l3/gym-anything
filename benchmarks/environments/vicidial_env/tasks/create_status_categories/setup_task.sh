#!/bin/bash
set -e

echo "=== Setting up Create Status Categories Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Clean up any existing target data to ensure a clean start
echo "Cleaning up target categories and statuses..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_status_categories WHERE vsc_id IN ('SALES','DNCLST','FOLLOWUP','NOANSWER');" 2>/dev/null || true

docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_statuses WHERE status IN ('SOLD','UPGRD','DNCREQ','CBPEND','NOPICK');" 2>/dev/null || true

# Record initial counts (should be baseline without our targets)
docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_status_categories;" > /tmp/initial_cat_count.txt

docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_statuses;" > /tmp/initial_status_count.txt

# Launch Firefox to Admin Panel
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Start URL
START_URL="${VICIDIAL_ADMIN_URL}"
su - ga -c "DISPLAY=:1 firefox '${START_URL}' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla|vicidial" 30 || true

# Maximize
focus_firefox
maximize_active_window

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="