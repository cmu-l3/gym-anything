#!/bin/bash
# Setup script for Fly Ash Concrete Scenario task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions if utils not found
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Fly Ash Concrete Scenario task ==="

# 1. Clean up previous artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/fly_ash_concrete_lcia.csv 2>/dev/null || true

# 2. Record Task Start Time (Critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure Import Data is Available
mkdir -p "/home/ga/LCA_Imports"
mkdir -p "/home/ga/LCA_Results"
chown -R ga:ga "/home/ga/LCA_Imports" "/home/ga/LCA_Results"

# Check/Copy USLCI Database
if [ ! -f "/home/ga/LCA_Imports/uslci_database.zip" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp "/opt/openlca_data/uslci_database.zip" "/home/ga/LCA_Imports/"
        echo "Copied USLCI database to imports folder."
    else
        echo "WARNING: USLCI database source not found!"
    fi
fi

# Check/Copy LCIA Methods
if [ ! -f "/home/ga/LCA_Imports/lcia_methods.zip" ]; then
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        cp "/opt/openlca_data/lcia_methods.zip" "/home/ga/LCA_Imports/"
        echo "Copied LCIA methods to imports folder."
    fi
fi
chown -R ga:ga "/home/ga/LCA_Imports"

# 4. Record Initial DB State (to detect if new processes are created)
# We can't query Derby yet if no DB exists, but we can count directories
DB_DIR="/home/ga/openLCA-data-1.4/databases"
INITIAL_DB_EXISTS="false"
INITIAL_PROCESS_COUNT=0
INITIAL_PS_COUNT=0

if [ -d "$DB_DIR" ] && [ "$(ls -A $DB_DIR)" ]; then
    # Try to find the largest DB to query
    LARGEST_DB=$(du -s "$DB_DIR"/* | sort -nr | head -1 | awk '{print $2}')
    if [ -n "$LARGEST_DB" ]; then
        INITIAL_DB_EXISTS="true"
        # We try to query, but OpenLCA might lock it if running. 
        # Since we haven't launched OpenLCA yet, it should be safe if valid.
        # However, derby_query function might rely on classpath setup in utils.
        # For simplicity in setup, we'll just record that it exists.
    fi
fi

# Record these baselines to a temp file
cat > /tmp/initial_state.json << EOF
{
  "db_exists": $INITIAL_DB_EXISTS,
  "timestamp": $(date +%s)
}
EOF

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Window Management
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "openLCA" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="