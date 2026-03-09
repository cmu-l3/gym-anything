#!/bin/bash
echo "=== Setting up configure_station_binding_scconfig task ==="

source /workspace/scripts/task_utils.sh

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Record initial binding state ─────────────────────────────────────────

echo "--- Recording initial state ---"

# Check for existing key files (SeisComP station bindings)
BINDINGS_DIR="$SEISCOMP_ROOT/etc/key"
mkdir -p "$BINDINGS_DIR"

INITIAL_BINDING_COUNT=$(ls "$BINDINGS_DIR"/station_GE_TOLI* 2>/dev/null | wc -l)
echo "$INITIAL_BINDING_COUNT" > /tmp/initial_binding_count
echo "Initial bindings for GE.TOLI: $INITIAL_BINDING_COUNT"

# Remove any existing binding for GE.TOLI to ensure clean start state
rm -f "$BINDINGS_DIR/station_GE_TOLI" 2>/dev/null || true
rm -f "$BINDINGS_DIR/station_GE_TOLI_global" 2>/dev/null || true

# Record clean state
echo "0" > /tmp/initial_binding_count

# ─── 3. Verify station inventory is loaded ────────────────────────────────────

echo "--- Verifying station inventory ---"

STATION_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Station WHERE code='TOLI'" 2>/dev/null || echo "0")
echo "Station TOLI in database: $STATION_COUNT"

if [ "$STATION_COUNT" = "0" ] || [ -z "$STATION_COUNT" ]; then
    echo "Station TOLI not found in database. Inventory may not have been imported."
    echo "scconfig should still show the station if inventory XML is available."
fi

# ─── 4. Kill any existing scconfig instances ──────────────────────────────────

echo "--- Preparing scconfig ---"
kill_seiscomp_gui scconfig

# ─── 5. Launch scconfig ──────────────────────────────────────────────────────

echo "--- Launching scconfig ---"
launch_seiscomp_gui scconfig "--plugins dbmysql"

# Wait for scconfig window to appear
wait_for_window "scconfig" 60 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30

sleep 3

# ─── 6. Dismiss any startup dialogs ──────────────────────────────────────────

dismiss_dialogs 2

# ─── 7. Focus and maximize scconfig window ────────────────────────────────────

focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"

sleep 2

# ─── 8. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/task_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scconfig should be visible."
echo "Agent should navigate to Bindings panel and add global binding for GE.TOLI."
