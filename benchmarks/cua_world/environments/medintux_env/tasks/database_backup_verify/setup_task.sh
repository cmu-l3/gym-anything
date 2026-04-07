#!/bin/bash
set -e
echo "=== Setting up database_backup_verify task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
echo "Ensuring MySQL is running..."
if ! pgrep -f "mysqld" > /dev/null; then
    systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
    sleep 5
fi

# Wait for MySQL readiness
for i in $(seq 1 30); do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL is ready."
        break
    fi
    sleep 1
done

# Verify source databases exist; if not, try to restore from environment defaults
# (The environment installation should have loaded these, but we ensure state here)
DATABASES=("DrTuxTest" "MedicaTuxTest" "CIM10Test" "CCAMTest")
for DB in "${DATABASES[@]}"; do
    EXISTS=$(mysql -u root -N -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB'" 2>/dev/null || echo "")
    if [ -z "$EXISTS" ]; then
        echo "WARNING: Database $DB missing. Attempting to create empty placeholder (environment should have provided this)."
        mysql -u root -e "CREATE DATABASE $DB;"
    fi
done

# Clean up any artifacts from previous runs
rm -rf /home/ga/MedinTux_Backups 2>/dev/null || true

# Drop any existing verification databases to ensure a clean slate
for DB in "${DATABASES[@]}"; do
    mysql -u root -e "DROP DATABASE IF EXISTS ${DB}_verify;" 2>/dev/null || true
done

# Ensure 'ga' user has a terminal open
if ! pgrep -f "xterm" > /dev/null; then
    su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'MedinTux Admin Terminal' &" 2>/dev/null || true
    sleep 2
fi

# Maximize terminal
DISPLAY=:1 wmctrl -r "MedinTux Admin Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "MedinTux Admin Terminal" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="