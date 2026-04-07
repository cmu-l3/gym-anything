#!/bin/bash
echo "=== Setting up batch_import_legacy_events task ==="

source /workspace/scripts/task_utils.sh

# 1. Start SeisComP messaging server
echo "Ensuring scmaster is running..."
ensure_scmaster_running

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Prepare the CSV Data
echo "Generating legacy_events.csv..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/legacy_events.csv << 'CSVEOF'
time,lat,lon,depth,mag,mag_type
2024-01-01T07:12:12.40Z,37.204,136.945,10.0,5.7,mb
2024-01-01T07:18:25.10Z,37.218,136.852,10.0,4.9,mb
2024-01-01T07:23:59.80Z,37.362,137.059,10.0,5.2,mb
2024-01-01T07:46:16.20Z,37.108,136.680,10.0,5.6,mb
2024-01-01T07:53:14.50Z,37.379,137.284,10.0,4.8,mb
CSVEOF

# Ensure permissions
chown -R ga:ga /home/ga/Documents

# 4. Clean up any previous attempts (anti-gaming & state reset)
echo "Cleaning up any existing target records or files..."
mysql -u sysop -psysop seiscomp -e "
DELETE FROM Event WHERE creationInfo_agencyID='LEGACY_IMPORT';
DELETE FROM Origin WHERE creationInfo_agencyID='LEGACY_IMPORT';
DELETE FROM Magnitude WHERE creationInfo_agencyID='LEGACY_IMPORT';
" 2>/dev/null || true

rm -f /home/ga/Documents/csv_to_scml.py
rm -f /home/ga/Documents/legacy_events.scml
rm -f /tmp/task_result.json

# 5. Open a terminal for the agent
if ! pgrep -x "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Documents &"
    sleep 2
fi

# Maximize the terminal for visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="