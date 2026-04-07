#!/bin/bash
echo "=== Setting up configure_magnitude_pipeline task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure SeisComP services (MariaDB and scmaster) are running
echo "Ensuring background services are running..."
systemctl start mariadb 2>/dev/null || true
sleep 2
ensure_scmaster_running

# Reset configuration files to a clean state
echo "Resetting configuration files..."
rm -f "$SEISCOMP_ROOT/etc/scamp.cfg"
rm -f "$SEISCOMP_ROOT/etc/scmag.cfg"
rm -f /home/ga/scamp_config_dump.txt
rm -f /home/ga/scmag_config_dump.txt

# Ensure defaults don't interfere
rm -f "$SEISCOMP_ROOT/etc/defaults/scamp.cfg"
rm -f "$SEISCOMP_ROOT/etc/defaults/scmag.cfg"

# Ensure correct ownership
chown -R ga:ga "$SEISCOMP_ROOT/etc"
chown -R ga:ga /home/ga

# Launch a terminal for the agent with pre-loaded environment variables
echo "Launching terminal..."
kill_seiscomp_gui "gnome-terminal" 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal --maximize -- bash -c '
export SEISCOMP_ROOT=/home/ga/seiscomp
export PATH=\$SEISCOMP_ROOT/bin:\$PATH
export LD_LIBRARY_PATH=\$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH
export PYTHONPATH=\$SEISCOMP_ROOT/lib/python:\$PYTHONPATH
echo \"=== SeisComP Environment Ready ===\"
echo \"SEISCOMP_ROOT=\$SEISCOMP_ROOT\"
echo \"\"
echo \"Task: Configure scamp and scmag magnitude processing parameters.\"
echo \"Configuration directory: \$SEISCOMP_ROOT/etc/\"
echo \"\"
exec bash
'" &

# Wait for terminal window to appear
sleep 3
wait_for_window "Terminal" 10 || wait_for_window "ga@" 10 || true

# Maximize and focus terminal
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot showing clean terminal
echo "Capturing initial state..."
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="