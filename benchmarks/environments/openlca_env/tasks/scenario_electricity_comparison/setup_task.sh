#!/bin/bash
# Setup script for Scenario Electricity Comparison task

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Scenario Electricity Comparison task ==="

rm -f /tmp/task_result.json 2>/dev/null || true

RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

INITIAL_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/ 2>/dev/null | wc -l)
echo "$INITIAL_RESULT_COUNT" > /tmp/initial_result_count
date +%s > /tmp/task_start_timestamp

# Ensure data files are available
for ZIP_SRC in "/opt/openlca_data/uslci_database.zip" "/opt/openlca_data/lcia_methods.zip"; do
    ZIP_NAME=$(basename "$ZIP_SRC")
    ZIP_DST="/home/ga/LCA_Imports/$ZIP_NAME"
    if [ ! -f "$ZIP_DST" ] && [ -f "$ZIP_SRC" ]; then
        mkdir -p "/home/ga/LCA_Imports"
        cp "$ZIP_SRC" "$ZIP_DST"
        chown ga:ga "$ZIP_DST"
        echo "Copied $ZIP_NAME"
    fi
done

INITIAL_DB_COUNT=$(count_openlca_databases 2>/dev/null || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

echo "USLCI zip: $([ -f '/home/ga/LCA_Imports/uslci_database.zip' ] && echo 'available' || echo 'NOT FOUND')"
echo "LCIA zip:  $([ -f '/home/ga/LCA_Imports/lcia_methods.zip' ] && echo 'available' || echo 'NOT FOUND')"

echo ""
echo "Launching OpenLCA..."
launch_openlca 180

sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Scenario Electricity Comparison task setup complete ==="
echo "Required: TWO product systems (coal electricity + natural gas electricity)"
echo "Required output: ~/LCA_Results/electricity_scenarios.csv"
echo "  with GWP + Acidification for both scenarios and % GWP reduction"
