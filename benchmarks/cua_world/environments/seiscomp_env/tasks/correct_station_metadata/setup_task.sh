#!/bin/bash
echo "=== Setting up correct_station_metadata task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure MariaDB and scmaster are running
echo "--- Ensuring SeisComP services are running ---"
systemctl start mariadb || true
ensure_scmaster_running

# 2. Reset the environment and ensure GE.BKB has a known incorrect elevation
echo "--- Preparing database state ---"

# First, ensure inventory tables exist and GE network is present
TABLE_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Station;" 2>/dev/null || echo "0")
if [ "$TABLE_COUNT" = "0" ]; then
    echo "WARNING: Station table is empty. Attempting to re-import inventory..."
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        seiscomp exec scdb --plugins dbmysql -i $SEISCOMP_ROOT/var/lib/inventory/ge_stations.scml \
        -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
fi

# Set GE.BKB elevation to a specific incorrect value (132.0) to ensure the agent has to change it
mysql -u sysop -psysop seiscomp -e "UPDATE Station SET elevation = 132.0 WHERE code = 'BKB';" 2>/dev/null || true

# 3. Record initial elevations of all GE stations for anti-gaming (collateral damage check)
echo "--- Recording initial station elevations ---"
mysql -u sysop -psysop seiscomp -N -e "SELECT code, elevation FROM Station WHERE code IN ('TOLI', 'GSI', 'KWP', 'SANI', 'BKB');" > /tmp/initial_elevations.txt 2>/dev/null || true

cat /tmp/initial_elevations.txt

# 4. Clean up any previous task artifacts
rm -f /home/ga/seiscomp/var/lib/inventory/corrected_inventory.xml
rm -f /home/ga/station_correction_report.txt
rm -f /tmp/task_result.json

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

# 6. Launch a terminal for the agent
echo "--- Launching terminal ---"
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
sleep 3
focus_and_maximize "Terminal"

# 7. Take initial screenshot
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="