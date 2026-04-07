#!/bin/bash
echo "=== Setting up compute_broadband_magnitudes_scamp task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure SeisComP services are running
ensure_scmaster_running

# Clean up any potential previous state
rm -f /home/ga/Documents/noto_reprocessed.scml
rm -f /home/ga/.seiscomp/scamp.cfg
rm -f /home/ga/.seiscomp/scmag.cfg
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/.seiscomp

# Verify the input event file exists
if [ ! -f "$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml" ]; then
    echo "WARNING: Event SCML file missing. Attempting to generate it..."
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
        python3 /workspace/scripts/convert_quakeml.py \
        $SEISCOMP_ROOT/var/lib/events/noto_earthquake.xml \
        $SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml" 2>/dev/null || true
fi

# Open a terminal for the user to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Opening terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Maximize the terminal window
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="