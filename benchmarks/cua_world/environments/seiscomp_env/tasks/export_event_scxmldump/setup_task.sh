#!/bin/bash
echo "=== Setting up export_event_scxmldump task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure MariaDB is running ────────────────────────────────────────────
echo "--- Ensuring MariaDB is running ---"
systemctl start mariadb || true
for i in $(seq 1 20); do
    if mysqladmin ping -h localhost 2>/dev/null; then
        echo "MariaDB is ready"
        break
    fi
    sleep 2
done

# ─── 2. Ensure scmaster is running ───────────────────────────────────────────
echo "--- Ensuring scmaster is running ---"
ensure_scmaster_running

# ─── 3. Verify event data exists in database ─────────────────────────────────
echo "--- Verifying event data in database ---"
EVENT_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT po.publicID FROM Event e JOIN PublicObject po ON e._oid = po._oid LIMIT 1" 2>/dev/null)

if [ -z "$EVENT_ID" ]; then
    echo "ERROR: No event found in database. Aborting."
    exit 1
fi
echo "Event ID verified: $EVENT_ID"

# ─── 4. Prepare output directory (clean state) ───────────────────────────────
echo "--- Preparing clean output state ---"
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
rm -f /home/ga/Documents/noto_export.xml

# ─── 5. Open a terminal window for the agent ─────────────────────────────────
echo "--- Opening terminal ---"
pkill -f "gnome-terminal" 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority \
    gnome-terminal --maximize -- bash -c '\
    source ~/.bashrc; \
    clear; \
    echo \"==================================================\"; \
    echo \"               SeisComP CLI Export Task           \"; \
    echo \"==================================================\"; \
    echo \"Environment ready. SeisComP tools available.\"; \
    echo \"Database: mysql://sysop:sysop@localhost/seiscomp\"; \
    echo \"\"; \
    exec bash'" &
sleep 3

# Focus and maximize the terminal
wait_for_window "Terminal" 10 || true
focus_and_maximize "Terminal" || true
sleep 1

# ─── 6. Take initial screenshot ──────────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="