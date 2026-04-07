#!/bin/bash
echo "=== Setting up export_to_stl task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Kill any running MGED instance
kill_mged

# Clean previous output
rm -f /home/ga/Documents/BRLCAD/havoc_export.stl

# Verify havoc.g is available (official BRL-CAD AH-64 Apache helicopter model)
if [ ! -f /opt/brlcad_samples/havoc.g ] || \
   [ "$(stat -c%s /opt/brlcad_samples/havoc.g 2>/dev/null || echo 0)" -lt 1000 ]; then
    echo "WARNING: havoc.g not found, falling back to m35.g..."
    if [ -f /opt/brlcad_samples/m35.g ]; then
        cp /opt/brlcad_samples/m35.g /home/ga/Documents/BRLCAD/havoc.g
    else
        echo "ERROR: No suitable .g database found"
        exit 1
    fi
else
    cp /opt/brlcad_samples/havoc.g /home/ga/Documents/BRLCAD/havoc.g
fi

chown ga:ga /home/ga/Documents/BRLCAD/havoc.g
echo "havoc.g size: $(stat -c%s /home/ga/Documents/BRLCAD/havoc.g) bytes"

# Write .mgedrc to auto-draw the helicopter and list tops
write_mgedrc "tops" "e havoc" "ae 35 25" "autoview"

# Launch MGED with havoc.g
launch_mged /home/ga/Documents/BRLCAD/havoc.g

# Wait for MGED windows to appear
wait_for_mged 45

# Wait for .mgedrc after-script to execute
sleep 5

# Position windows: Command Window left, Graphics Window right
position_mged_windows
sleep 1

echo "=== export_to_stl task setup complete ==="
echo "MGED is running with havoc.g loaded."
echo "Active windows:"
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null || true
