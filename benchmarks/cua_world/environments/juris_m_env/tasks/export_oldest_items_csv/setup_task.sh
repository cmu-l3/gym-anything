#!/bin/bash
echo "=== Setting up export_oldest_items_csv task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists and is clean of previous output
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/oldest_precedents.csv
echo "Cleaned previous output file"

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # We will try to proceed anyway, forcing a Jurism restart might create it/locate it
fi

# Stop Jurism to allow DB access/injection
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject references to ensure we have the specific date range required
# The inject_references.py script adds:
# - Marbury v. Madison (1803)
# - The Path of the Law (1897)
# - Brown v. Board (1954)
# - Obergefell (2015) etc.
echo "Injecting legal references..."
python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: Reference injection had issues"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss any in-app alert dialogs
wait_and_dismiss_jurism_alerts 45

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target file: /home/ga/Documents/oldest_precedents.csv"