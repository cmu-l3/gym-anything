#!/bin/bash
set -e

echo "=== Setting up configure_scqc_parameters_scconfig ==="

source /workspace/scripts/task_utils.sh

TASK="configure_scqc_parameters_scconfig"
SCQC_CFG="$SEISCOMP_ROOT/etc/scqc.cfg"

ensure_scmaster_running

if [ -f "$SCQC_CFG" ]; then
    cp "$SCQC_CFG" "/tmp/${TASK}_initial_scqc.cfg" 2>/dev/null || true
fi
rm -f "$SCQC_CFG" 2>/dev/null || true

date +%s > "/tmp/${TASK}_start_ts"

kill_seiscomp_gui scconfig
launch_seiscomp_gui scconfig "--plugins dbmysql"

wait_for_window "scconfig" 60 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30
sleep 3
dismiss_dialogs 2
focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"
sleep 2
take_screenshot "/tmp/${TASK}_start.png"

echo "=== Setup complete ==="
