#!/bin/bash
set -e
echo "=== Setting up remote_observatory_fault_recovery task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/verification
rm -rf /home/ga/Images/captures/*
rm -f /home/ga/Documents/fault_log.txt
rm -f /home/ga/Documents/fault_resolution.txt
rm -f /tmp/task_result.json

mkdir -p /home/ga/Images/captures
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images
chown -R ga:ga /home/ga/Documents

# ── 2. ERROR INJECTION: Seed stale FITS files ─────────────────────────
# These mimic files left over from a previous session and MUST NOT be
# counted as the verification images.
touch -t 202401010000 /home/ga/Images/captures/old_session_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/captures/old_session_002.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/captures/old_session_003.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Images/captures

# ── 3. Record task start time ─────────────────────────────────────────
# Crucial: recorded after creating the old stale files
date +%s > /tmp/task_start_time.txt

# ── 4. Start INDI and Connect Devices (to seed faults) ────────────────
ensure_indi_running
sleep 2
connect_all_devices
sleep 2

# ── 5. Seed Specific Faults ───────────────────────────────────────────
echo "Seeding faults..."

# Fault 4 & 5: Focuser runaway to 99000, Corrupt Upload Directory, Telescope Parked
indi_setprop "Telescope Simulator.TELESCOPE_PARK.PARK=On" 2>/dev/null || true
indi_setprop "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION=99000" 2>/dev/null || true
indi_setprop "CCD Simulator.UPLOAD_SETTINGS.UPLOAD_DIR=/nonexistent/path/" 2>/dev/null || true
indi_setprop "CCD Simulator.UPLOAD_MODE.UPLOAD_LOCAL=On" 2>/dev/null || true
sleep 2

# Fault 1, 2, 3: Disconnect Telescope, CCD, and Filter Wheel
indi_setprop "Telescope Simulator.CONNECTION.DISCONNECT=On" 2>/dev/null || true
indi_setprop "CCD Simulator.CONNECTION.DISCONNECT=On" 2>/dev/null || true
indi_setprop "Filter Simulator.CONNECTION.DISCONNECT=On" 2>/dev/null || true
sleep 1

# ── 6. Create the Fault Log Document ──────────────────────────────────
cat > /home/ga/Documents/fault_log.txt << 'EOF'
================================================================================
 REMOTE OBSERVATORY MONITORING SYSTEM — FAULT REPORT
 Observatory: Hilltop Remote Observatory (MPC Code H06)
================================================================================

ALERT LEVEL: CRITICAL — Multiple subsystem failures detected

--- FAULT TIMELINE ---

[02:14:07 UTC] WARNING: Telescope Simulator — tracking rate deviation exceeded 5"/s
[02:14:09 UTC] ERROR:   Telescope Simulator — communication timeout (no response in 10s)
[02:14:09 UTC] FAULT:   Telescope Simulator — DISCONNECTED. Mount parked by safety watchdog.

[02:14:11 UTC] WARNING: CCD Simulator — frame readout interrupted mid-transfer
[02:14:13 UTC] ERROR:   CCD Simulator — communication timeout (no response in 10s)  
[02:14:13 UTC] FAULT:   CCD Simulator — DISCONNECTED.

[02:14:14 UTC] WARNING: Filter Simulator — command queue overflow
[02:14:15 UTC] FAULT:   Filter Simulator — DISCONNECTED.

[02:15:01 UTC] WARNING: Focuser Simulator — position readout: 99000 (LIMIT)
[02:15:01 UTC] FAULT:   Focuser Simulator — runaway motion detected during crash.
                         Current position 99000 is far beyond normal operating range
                         (nominal focus ~25000-35000).

[02:15:30 UTC] WARNING: CCD upload configuration corrupted.
                         Upload directory set to: /nonexistent/path/
                         Images will NOT be saved until corrected.

[02:16:00 UTC] INFO:    Automated session ABORTED. All pending targets cancelled.
[02:16:00 UTC] INFO:    Watchdog parking telescope for safety.

--- RECOVERY PROCEDURE ---
  1. Reconnect all disconnected devices via INDI
  2. Unpark telescope mount
  3. Reset focuser to nominal operating range
  4. Correct CCD upload directory configuration
  5. Perform standard verification observation:
     - Target: Vega (alpha Lyrae), RA 18h 36m 56.3s, Dec +38 47' 01.3"
     - Filter: V-band
     - Exposure: 10 seconds, LIGHT frame
     - Save verification images to: /home/ga/Images/verification/
  6. File fault resolution report to: /home/ga/Documents/fault_resolution.txt
     Include: each fault encountered, action taken, final device status

================================================================================
 END OF FAULT REPORT
================================================================================
EOF
chown ga:ga /home/ga/Documents/fault_log.txt

# ── 7. Ensure KStars is running ────────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Fault log available at ~/Documents/fault_log.txt"