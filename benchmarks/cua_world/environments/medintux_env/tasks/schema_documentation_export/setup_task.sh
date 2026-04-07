#!/bin/bash
set -e
echo "=== Setting up Schema Documentation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
echo "Checking MySQL status..."
if ! pgrep -x "mysqld" > /dev/null; then
    echo "Starting MySQL..."
    systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
    sleep 5
fi

# Wait for MySQL readiness
for i in {1..15}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL is ready."
        break
    fi
    sleep 2
done

# Verify DrTuxTest database exists and has data
DB_CHECK=$(mysql -u root -N -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='DrTuxTest'" 2>/dev/null || echo "0")
echo "DrTuxTest tables found: $DB_CHECK"

if [ "$DB_CHECK" -lt 5 ]; then
    echo "ERROR: DrTuxTest database seems empty or missing. Attempting to reload..."
    # Try to reload standard dumps if they exist
    SQL_DIR="/home/ga/.wine/drive_c/MedinTux-2.16/Programmes/set_bases/bin/SqlCreateTable"
    if [ -f "$SQL_DIR/Dump_DrTuxTest.sql" ]; then
        mysql -u root DrTuxTest < "$SQL_DIR/Dump_DrTuxTest.sql" 2>/dev/null || true
    fi
fi

# Clean up any previous run artifacts
rm -f /home/ga/Documents/drtuxtest_schema.json
rm -f /tmp/ground_truth.json
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Ensure MedinTux is running (provides visual context, though strictly data task)
ensure_medintux_running || true

# Open a terminal for the agent to work in
if ! pgrep -f "xterm" > /dev/null; then
    su - ga -c "DISPLAY=:1 xterm -geometry 100x30+50+50 -title 'Terminal - Database Task' &"
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="