#!/bin/bash
echo "=== Setting up configure_module_bindings_three_stations_scconfig task ==="

source /workspace/scripts/task_utils.sh

TASK="configure_module_bindings_three_stations_scconfig"
BINDINGS_DIR="$SEISCOMP_ROOT/etc/key"
STATIONS="GSI BKB SANI"
MODULES="scautopick scamp"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Reset station key files — remove scautopick and scamp bindings ────────

echo "--- Clearing existing module bindings for target stations ---"
mkdir -p "$BINDINGS_DIR"

for STA in $STATIONS; do
    KEY_FILE="$BINDINGS_DIR/station_GE_${STA}"

    if [ -f "$KEY_FILE" ]; then
        # Remove scautopick and scamp lines while keeping other content
        grep -v "^scautopick" "$KEY_FILE" | grep -v "^scamp" > "${KEY_FILE}.tmp" 2>/dev/null || true
        mv "${KEY_FILE}.tmp" "$KEY_FILE" 2>/dev/null || true
        echo "  Cleared module bindings from $KEY_FILE"
    else
        # Create empty key file (station is known but has no bindings)
        touch "$KEY_FILE"
        echo "  Created empty key file: $KEY_FILE"
    fi
done

chown -R ga:ga "$BINDINGS_DIR" 2>/dev/null || true

# ─── 3. Record baseline state ────────────────────────────────────────────────

echo "--- Recording baseline state ---"

# Count of station key files that have scautopick AND scamp bindings
INITIAL_SCAUTOPICK_COUNT=0
INITIAL_SCAMP_COUNT=0
for STA in $STATIONS; do
    KEY_FILE="$BINDINGS_DIR/station_GE_${STA}"
    if [ -f "$KEY_FILE" ] && grep -q "^scautopick" "$KEY_FILE" 2>/dev/null; then
        INITIAL_SCAUTOPICK_COUNT=$((INITIAL_SCAUTOPICK_COUNT + 1))
    fi
    if [ -f "$KEY_FILE" ] && grep -q "^scamp" "$KEY_FILE" 2>/dev/null; then
        INITIAL_SCAMP_COUNT=$((INITIAL_SCAMP_COUNT + 1))
    fi
done

echo "$INITIAL_SCAUTOPICK_COUNT" > /tmp/${TASK}_initial_scautopick_count
echo "$INITIAL_SCAMP_COUNT" > /tmp/${TASK}_initial_scamp_count
date +%s > /tmp/${TASK}_start_ts

echo "Initial stations with scautopick: $INITIAL_SCAUTOPICK_COUNT"
echo "Initial stations with scamp: $INITIAL_SCAMP_COUNT"

# ─── 4. Kill any existing scconfig, launch fresh ─────────────────────────────

echo "--- Launching scconfig ---"
kill_seiscomp_gui scconfig

launch_seiscomp_gui scconfig "--plugins dbmysql"

wait_for_window "scconfig" 60 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30

sleep 3
dismiss_dialogs 2
focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"
sleep 2

# ─── 5. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scconfig is open. Agent must:"
echo "  1. Navigate to Bindings panel"
echo "  2. Add 'scautopick:default' binding to GE.GSI, GE.BKB, and GE.SANI"
echo "  3. Add 'scamp:default' binding to GE.GSI, GE.BKB, and GE.SANI"
echo "  4. Save and Update configuration"
echo "Key file location: $BINDINGS_DIR"
