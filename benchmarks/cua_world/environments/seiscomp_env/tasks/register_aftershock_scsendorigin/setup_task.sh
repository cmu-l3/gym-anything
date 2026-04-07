#!/bin/bash
echo "=== Setting up task: register_aftershock_scsendorigin ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure MariaDB is running
systemctl start mariadb 2>/dev/null || true
for i in $(seq 1 15); do
    if mysqladmin ping -h localhost 2>/dev/null; then
        echo "MariaDB is ready"
        break
    fi
    sleep 1
done

# Ensure scmaster is running (required for scsendorigin messaging)
ensure_scmaster_running

# Record initial origin count in database
INITIAL_ORIGIN_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Origin" 2>/dev/null || echo "0")
echo "$INITIAL_ORIGIN_COUNT" > /tmp/initial_origin_count.txt
echo "Initial origin count: $INITIAL_ORIGIN_COUNT"

# Clean up any previous task artifacts
rm -f /home/ga/aftershock_report.txt

# Open a terminal for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal\|bash\|term"; then
    echo "Opening terminal..."
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xfce4-terminal --maximize &" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal --maximize &" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xterm -maximized &" 2>/dev/null || true
    sleep 3
fi

# Focus terminal
for term_pattern in "Terminal" "terminal" "bash" "xterm"; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$term_pattern"; then
        focus_and_maximize "$term_pattern"
        break
    fi
done

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="