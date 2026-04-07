#!/bin/bash
echo "=== Setting up generate_station_inventory_python task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Ensure SeisComP services (specifically scmaster and mariadb) are running
echo "Ensuring MariaDB and scmaster are running..."
systemctl start mariadb 2>/dev/null || true
ensure_scmaster_running 2>/dev/null || true

# 2. Clean up any existing state (Anti-gaming & Idempotency)
echo "Cleaning up any existing 'TR' network from database..."
mysql -u sysop -psysop seiscomp -e "
DELETE FROM Stream WHERE _parent_oid IN (SELECT _oid FROM SensorLocation WHERE _parent_oid IN (SELECT _oid FROM Station WHERE code='RAPID'));
DELETE FROM SensorLocation WHERE _parent_oid IN (SELECT _oid FROM Station WHERE code='RAPID');
DELETE FROM Station WHERE code='RAPID';
DELETE FROM Network WHERE code='TR';
" 2>/dev/null || true

# Remove any existing agent files
rm -f /home/ga/rapid_station.scml 2>/dev/null || true
rm -f /home/ga/create_inventory.py 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 3. Open a terminal for the agent
echo "Opening terminal for agent..."
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30+100+100 &"
    sleep 3
fi

# Maximize the terminal to ensure good visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Clear terminal screen
DISPLAY=:1 xdotool type "clear"
DISPLAY=:1 xdotool key Return
sleep 1

# 4. Take initial screenshot
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="