#!/bin/bash
# Setup script for Monte Carlo Uncertainty Quantification task

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Monte Carlo Uncertainty Quantification task ==="

rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/monte_carlo_uncertainty_result.json 2>/dev/null || true

RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

INITIAL_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/ 2>/dev/null | wc -l)
echo "$INITIAL_RESULT_COUNT" > /tmp/initial_result_count
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Ensure USLCI zip is available
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

# Ensure LCIA methods zip is available
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

echo "USLCI zip: $([ -f "$USLCI_ZIP" ] && echo "available ($(du -sh "$USLCI_ZIP" | cut -f1))" || echo "NOT FOUND")"
echo "LCIA zip:  $([ -f "$LCIA_ZIP" ] && echo "available ($(du -sh "$LCIA_ZIP" | cut -f1))" || echo "NOT FOUND")"

INITIAL_DB_COUNT=$(count_openlca_databases 2>/dev/null || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count
echo "Initial database count: $INITIAL_DB_COUNT"

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
echo "=== Monte Carlo Uncertainty task setup complete ==="
echo "Available resources:"
echo "  USLCI database: ~/LCA_Imports/uslci_database.zip"
echo "  LCIA methods:   ~/LCA_Imports/lcia_methods.zip"
echo "  Target: coal electricity generation process in USLCI"
echo "  Results dir:    ~/LCA_Results/"
