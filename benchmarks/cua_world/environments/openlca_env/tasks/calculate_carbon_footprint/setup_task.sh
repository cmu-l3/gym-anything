#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Calculate Carbon Footprint task ==="

# ============================================================
# SELF-CONTAINED SETUP: Verify prerequisites
# ============================================================

# Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true

# Record initial state
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

INITIAL_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/* 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_RESULT_COUNT" > /tmp/initial_result_count
echo "Initial result file count: $INITIAL_RESULT_COUNT"

# Check for USLCI database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
USLCI_DB=$(ensure_uslci_database)

if [ -z "$USLCI_DB" ]; then
    echo "No USLCI database found. Agent will need to create and import first."
else
    echo "Found database: $(basename "$USLCI_DB") ($(du -sh "$USLCI_DB" 2>/dev/null | cut -f1))"
fi

# Check LCIA methods availability
LCIA_FILE=$(ensure_lcia_methods)
if [ -n "$LCIA_FILE" ]; then
    echo "LCIA methods available at: $LCIA_FILE"
else
    echo "LCIA methods pack not found - agent will use whatever methods are available in openLCA."
fi

# ============================================================
# Launch OpenLCA
# ============================================================

echo ""
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 2
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "OpenLCA window maximized"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Task setup complete ==="
