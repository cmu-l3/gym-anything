#!/bin/bash
set -euo pipefail

echo "=== Setting up jupiter_orbit_insertion_capture task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts and ensure directories exist
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/joi_specifications.txt
rm -f /home/ga/Documents/missions/joi_sim.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the specifications file
cat > /home/ga/Desktop/joi_specifications.txt << 'SPECEOF'
=== JUPITER FLAGSHIP MISSION: JOI DESIGN SPECIFICATION ===

1. INCOMING STATE (Jupiter-centered, Keplerian)
   Central Body: Jupiter
   Coordinate System: JupiterMJ2000Eq (or similar Jupiter-centered Earth-Mean-Equator)
   SMA: -1500000.0 km (Hyperbolic approach)
   ECC: 1.05
   INC: 10.0 deg
   RAAN: 45.0 deg
   AOP: 0.0 deg
   TA: -160.0 deg
   Epoch: 01 Jul 2030 12:00:00.000 UTCG

2. SPACECRAFT PROPERTIES
   Dry Mass: 2500 kg
   Fuel Mass: 1500 kg

3. MANEUVER REQUIREMENTS
   Burn Location: Exactly at Jupiter Periapsis (Perijove)
   Burn Type: Single Impulsive Burn, Retrograde (anti-velocity)
   Target Post-Burn Orbit: SMA = 9850000.0 km

4. OUTPUT REQUIREMENTS
   Generate a text file at: ~/GMAT_output/joi_results.txt
   The file must contain these exact keys with your computed values:
   required_deltav_m_s: <value in meters/second>
   final_sma_km: <value in km>
   final_eccentricity: <value>

=============================================================
SPECEOF

chown ga:ga /home/ga/Desktop/joi_specifications.txt

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

echo "=== Task Setup Complete ==="