#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up CSV Import Inventory task ==="

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Docker and SciNote are healthy
ensure_docker_healthy
wait_for_scinote_ready 120

# Record initial counts
INITIAL_REPO_COUNT=$(get_repository_count)
echo "${INITIAL_REPO_COUNT:-0}" > /tmp/initial_repo_count.txt

INITIAL_ROW_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows;" | tr -d '[:space:]')
echo "${INITIAL_ROW_COUNT:-0}" > /tmp/initial_row_count.txt

echo "Initial state: ${INITIAL_REPO_COUNT:-0} repositories, ${INITIAL_ROW_COUNT:-0} repository rows"

# ============================================================
# Create CSV file with real chemical data
# ============================================================

mkdir -p /home/ga/Documents

cat > /home/ga/Documents/chemical_inventory.csv << 'CSVEOF'
Name,CAS Number,Molecular Weight (g/mol),Boiling Point (°C),Supplier,Storage Location,Purity (%),Quantity (mL)
Acetone,67-64-1,58.08,56.05,Sigma-Aldrich,Cabinet A-1,99.5,2500
Methanol,67-56-1,32.04,64.70,Fisher Scientific,Cabinet A-2,99.9,2500
Ethanol,64-17-5,46.07,78.37,Sigma-Aldrich,Cabinet A-2,99.8,4000
Dichloromethane,75-09-2,84.93,39.60,Merck,Fume Hood B-1,99.5,2500
Chloroform,67-66-3,119.38,61.15,Fisher Scientific,Fume Hood B-1,99.0,1000
Diethyl Ether,60-29-7,74.12,34.60,Sigma-Aldrich,Flammables Cabinet C-1,99.7,1000
Hexane,110-54-3,86.18,69.00,Fisher Scientific,Cabinet A-3,95.0,2500
Toluene,108-88-3,92.14,110.60,Sigma-Aldrich,Cabinet A-3,99.8,2500
Dimethyl Sulfoxide,67-68-5,78.13,189.00,Merck,Shelf D-2,99.9,500
Tetrahydrofuran,109-99-9,72.11,66.00,Sigma-Aldrich,Flammables Cabinet C-1,99.5,1000
Acetonitrile,75-05-8,41.05,81.60,Fisher Scientific,Cabinet A-4,99.9,2500
Ethyl Acetate,141-78-6,88.11,77.10,Sigma-Aldrich,Cabinet A-4,99.5,2500
Isopropanol,67-63-0,60.10,82.60,Fisher Scientific,Cabinet A-2,99.7,4000
Dimethylformamide,68-12-2,73.09,153.00,Merck,Fume Hood B-2,99.8,500
Petroleum Ether,8032-32-4,82.20,40.00,Sigma-Aldrich,Flammables Cabinet C-2,95.0,2500
CSVEOF

chown ga:ga /home/ga/Documents/chemical_inventory.csv
chmod 644 /home/ga/Documents/chemical_inventory.csv

echo "CSV file created at /home/ga/Documents/chemical_inventory.csv with 15 chemicals"

# ============================================================
# Ensure Firefox is running and pointing to SciNote
# ============================================================

ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 5

# Maximize and focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Dismiss any popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== CSV Import Inventory task setup complete ==="