#!/bin/bash
# Pre-task setup for export_process_jsonld

set -e

echo "=== Setting up Export Process JSON-LD task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    # Minimal fallback
    function launch_openlca() {
        su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" &
        sleep 20
    }
    function take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# 1. Clean up previous results and state
rm -f /home/ga/LCA_Results/natural_gas_electricity.zip 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -rf /tmp/export_check 2>/dev/null || true

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure input data is available
mkdir -p /home/ga/LCA_Imports
mkdir -p /home/ga/LCA_Results
chown -R ga:ga /home/ga/LCA_Imports /home/ga/LCA_Results

USLCI_SRC="/opt/openlca_data/uslci_database.zip"
USLCI_DEST="/home/ga/LCA_Imports/uslci_database.zip"

if [ -f "$USLCI_SRC" ]; then
    if [ ! -f "$USLCI_DEST" ]; then
        echo "Copying USLCI database to imports folder..."
        cp "$USLCI_SRC" "$USLCI_DEST"
        chown ga:ga "$USLCI_DEST"
    fi
else
    echo "WARNING: USLCI source not found at $USLCI_SRC"
    # Create a dummy zip if real one missing (prevents immediate fail, though task is impossible)
    touch /tmp/dummy
    zip "$USLCI_DEST" /tmp/dummy
    chown ga:ga "$USLCI_DEST"
fi

# 4. Record initial DB state (should be low/zero if we want them to import)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
INITIAL_DB_COUNT=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Set window state
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "openLCA" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    echo "Maximizing OpenLCA window..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="