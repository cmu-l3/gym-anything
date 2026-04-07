#!/bin/bash
echo "=== Setting up manual_event_recovery_scolv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure SeisComP services are running ──────────────────────────────
echo "Ensuring SeisComP services are running..."
ensure_scmaster_running

# ─── 2. Prepare Database (Clean slate for events) ─────────────────────────
echo "Clearing pre-existing events from the database..."
# We leave the Inventory intact, but wipe out Events to force manual recovery
mysql -u sysop -psysop seiscomp -e "
    SET FOREIGN_KEY_CHECKS=0;
    TRUNCATE TABLE Event;
    TRUNCATE TABLE Origin;
    TRUNCATE TABLE Magnitude;
    TRUNCATE TABLE StationMagnitude;
    TRUNCATE TABLE Amplitude;
    TRUNCATE TABLE Pick;
    TRUNCATE TABLE Arrival;
    SET FOREIGN_KEY_CHECKS=1;
" 2>/dev/null

# ─── 3. Ensure global.cfg points to SDS archive ───────────────────────────
# Critical for scolv to compute magnitudes using archived waveforms
if ! grep -q "^recordstream\s*=\s*sdsarchive" "$SEISCOMP_ROOT/etc/global.cfg" 2>/dev/null; then
    echo "Configuring recordstream in global.cfg..."
    echo "recordstream = sdsarchive:///home/ga/seiscomp/var/lib/archive" >> "$SEISCOMP_ROOT/etc/global.cfg"
fi

# ─── 4. Create the alert text file ────────────────────────────────────────
echo "Creating USGS alert file..."
cat > /home/ga/Desktop/usgs_alert.txt << 'EOF'
URGENT - MISSED EVENT REPORT
----------------------------
Agency: USGS
Event: Noto Peninsula, Japan
Time: 2024-01-01 07:10:09.5 UTC
Lat: 37.498
Lon: 137.242
Depth: 10 km
Expected Magnitude: ~ M 7.5

ACTION REQUIRED:
1. Enter these parameters manually into SeisComP via scolv (Artificial Origin).
2. Commit origin.
3. Compute magnitude using local SDS archive data (GE network).
4. Export result to ~/recovered_event.xml.
EOF
chmod 644 /home/ga/Desktop/usgs_alert.txt
chown ga:ga /home/ga/Desktop/usgs_alert.txt

# Remove any pre-existing output file
rm -f /home/ga/recovered_event.xml 2>/dev/null

# ─── 5. Launch and configure scolv ────────────────────────────────────────
echo "Preparing scolv..."
kill_seiscomp_gui scolv

echo "Launching scolv..."
launch_seiscomp_gui scolv "-d mysql://sysop:sysop@localhost/seiscomp"

# Wait for scolv window to appear
wait_for_window "scolv" 45 || wait_for_window "Origin" 30

# Dismiss dialogs and maximize
dismiss_dialogs 2
focus_and_maximize "scolv" || focus_and_maximize "Origin"

# ─── 6. Final Setup Verification ──────────────────────────────────────────
sleep 2
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial_state.png

# Verify screenshot
if [ -f /tmp/task_initial_state.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Could not capture initial screenshot."
fi

echo "=== Task setup complete ==="