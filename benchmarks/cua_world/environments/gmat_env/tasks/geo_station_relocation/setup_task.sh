#!/bin/bash
set -euo pipefail

echo "=== Setting up geo_station_relocation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts and ensure clean workspace
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/relocation_directive.txt
rm -f /home/ga/Documents/missions/geo_relocation.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the Relocation Directive on the Desktop
cat > /home/ga/Desktop/relocation_directive.txt << 'SPECEOF'
============================================================
        SATELLITE RELOCATION DIRECTIVE - SRD-2025-0047
        Classification: UNCLASSIFIED / FOR OFFICIAL USE
============================================================

SATELLITE:      SATCOM-7 (NORAD ID 54821)
OPERATOR:       Atlantic Communications Corp.
DATE ISSUED:    15 Jun 2025

1. RELOCATION ORDER
   Current Slot:     105.0 deg West
   Target Slot:       75.0 deg West
   Drift Direction:   EASTWARD (+30.0 degrees)

2. CONSTRAINTS
   Maximum Drift Rate:   2.0 deg/day (ITU coordination limit)
   Minimum Drift Time:  15 days (thermal/momentum management)
   Maximum Drift Time:  45 days (service availability requirement)

3. SPACECRAFT PARAMETERS (at relocation epoch)
   Epoch:          01 Jul 2025 12:00:00.000 UTCG
   Coord. System:  EarthMJ2000Eq
   SMA:            42164.17 km
   ECC:            0.0003
   INC:            0.05 deg
   RAAN:           0.0 deg
   AOP:            0.0 deg
   TA:             0.0 deg
   
   DryMass:        3200 kg
   Cd:             2.2
   DragArea:       35.0 m^2
   Cr:             1.4
   SRPArea:        42.0 m^2

4. REQUIRED DELIVERABLES (Write to ~/GMAT_output/relocation_results.txt)
   - Drift orbit semi-major axis (km)
   - Drift rate (deg/day)  
   - Burn 1 delta-V (m/s)
   - Burn 2 delta-V (m/s)
   - Total delta-V (m/s)
   - Total drift duration (days)
   - Final longitude estimate (deg West)

5. NOTES
   - Eastward drift requires LOWERING the orbit (shorter period = faster angular rate).
   - Use an ImpulsiveBurn for Burn 1 (retrograde) and Burn 2 (prograde).
   - A standard two-body or J2 propagator is sufficient for this preliminary design.
============================================================
SPECEOF

chown ga:ga /home/ga/Desktop/relocation_directive.txt

# 4. Launch GMAT
echo "Launching GMAT..."
launch_gmat ""

echo "Waiting for GMAT window..."
WID=$(wait_for_gmat_window 60)

if [ -n "$WID" ]; then
    echo "GMAT window found: $WID"
    sleep 5
    dismiss_gmat_dialogs
    focus_gmat_window
    take_screenshot /tmp/task_initial_state.png
    echo "Initial screenshot captured."
else
    echo "ERROR: GMAT failed to start within timeout."
    exit 1
fi

echo "=== Task Setup Complete: Directive at ~/Desktop/relocation_directive.txt ==="