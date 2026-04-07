#!/bin/bash
echo "=== Setting up compute_pgv_amplitudes task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure SeisComP services are running
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# 2. Ensure clean state in database (Remove any existing PGV amplitudes)
echo "--- Cleaning up any existing PGV records ---"
seiscomp_db_query "DELETE FROM Amplitude WHERE type='PGV';" 2>/dev/null || true

# 3. Configure scamp to strictly NOT compute PGV yet (force agent to do it)
echo "--- Setting initial scamp configuration ---"
mkdir -p "$SEISCOMP_ROOT/etc"
echo "amplitudes = MLv" > "$SEISCOMP_ROOT/etc/scamp.cfg"
chown ga:ga "$SEISCOMP_ROOT/etc/scamp.cfg"

# 4. Verify Noto event is in the database
echo "--- Verifying Noto event in database ---"
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "Event not found, attempting to reimport..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    QML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.xml"
    
    # Convert from QuakeML if SCML is missing
    if [ ! -s "$SCML_FILE" ] && [ -s "$QML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
            python3 /workspace/scripts/convert_quakeml.py $QML_FILE $SCML_FILE" 2>/dev/null || true
    fi
    
    # Import into DB
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
        sleep 2
    fi
fi

# Ensure output directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 5. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 6. Set up the desktop environment for the agent (Open a terminal)
echo "--- Opening terminal for agent ---"
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga" &
sleep 4

# Maximize the terminal
focus_and_maximize "Terminal"

# 7. Take initial screenshot
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="