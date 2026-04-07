#!/bin/bash
set -euo pipefail

echo "=== Setting up lunar_dsn_ephemeris_generation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace to ensure no stale files exist
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/ephemeris_request.txt
rm -f /home/ga/Documents/missions/lunar_dsn.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Write the Mission Director Memo to the desktop
cat > /home/ga/Desktop/ephemeris_request.txt << 'MEMOEOF'
MEMORANDUM
To: Flight Dynamics Operations
From: Mission Director
Subject: Lunar Polar Mapper (LPM) - Ephemeris Generation for DSN & Science

We need the nominal 7-day trajectory ephemeris for the Lunar Polar Mapper (LPM) mission to schedule Deep Space Network (DSN) contacts and support the science team's instrument pointing planning.

Please configure the nominal lunar parking orbit in GMAT and generate the required ephemeris files.

INITIAL STATE (Coordinate System: Moon-centered MJ2000Eq)
Epoch: 01 Mar 2026 12:00:00.000 UTCG
SMA: 1838.14 km (~100 km circular)
ECC: 0.001
INC: 90.0 deg (polar)
RAAN: 45.0 deg
AOP: 0.0 deg
TA: 0.0 deg

SPACECRAFT PROPERTIES
Dry Mass: 800 kg
SRP Area: 5.0 m^2
Cr: 1.5
(Drag can be neglected for the Moon)

DYNAMICS / FORCE MODEL
- Central Body: Luna
- Gravity Field: Minimum 10x10 spherical harmonics (e.g., LP165)
- Third-Body perturbations: Earth, Sun
- Solar Radiation Pressure: Enabled

DELIVERABLES
Save your script to ~/Documents/missions/lunar_dsn.script, propagate the orbit for exactly 7 days, and configure EphemerisFile resources to output the following two files:

1. DSN Ephemeris
   - Format: CCSDS OEM (Orbit Ephemeris Message)
   - Target File: ~/GMAT_output/lunar_dsn.oem
   - Coordinate System: Moon-centered MJ2000Eq
   - Step Size: 60 seconds

2. Science Ephemeris
   - Format: SPICE SPK
   - Target File: ~/GMAT_output/lunar_science.bsp
   - Coordinate System: Moon-centered MJ2000Eq
   - Step Size: 60 seconds
MEMOEOF

chown ga:ga /home/ga/Desktop/ephemeris_request.txt

# 4. Launch GMAT Application
echo "Launching GMAT..."
launch_gmat ""

echo "Waiting for GMAT window..."
WID=$(wait_for_gmat_window 60)

if [ -n "$WID" ]; then
    echo "GMAT window found: $WID"
    sleep 5
    dismiss_gmat_dialogs
    focus_gmat_window
    
    # Allow UI to stabilize before screenshot
    sleep 2
    take_screenshot /tmp/task_initial_state.png
    echo "Initial screenshot captured."
else
    echo "ERROR: GMAT failed to start within timeout."
    exit 1
fi

echo "=== Task Setup Complete ==="