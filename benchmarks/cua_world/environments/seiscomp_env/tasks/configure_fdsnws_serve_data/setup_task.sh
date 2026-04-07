#!/bin/bash
echo "=== Setting up configure_fdsnws_serve_data task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure scmaster is running (messaging/database core)
ensure_scmaster_running
sleep 3

# Stop fdsnws if it's already running to ensure a clean slate
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp stop fdsnws" >/dev/null 2>&1 || true

# Remove any existing fdsnws configuration to force the agent to write it
rm -f "$SEISCOMP_ROOT/etc/fdsnws.cfg" 2>/dev/null || true

# Clean up any existing test directory
rm -rf /home/ga/fdsnws_test 2>/dev/null || true

# Verify database has the expected real data
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
STATION_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Station" 2>/dev/null || echo "0")
echo "Database state verified: $EVENT_COUNT events, $STATION_COUNT stations"

# Open a terminal for the agent
kill_seiscomp_gui gnome-terminal
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal --maximize -- bash -c 'source ~/.bashrc; clear; echo \"SeisComP FDSNWS Configuration Task\"; echo \"\"; exec bash'" &
sleep 3

# Focus and maximize the terminal
focus_and_maximize "Terminal" || focus_and_maximize "ga@ubuntu"

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="