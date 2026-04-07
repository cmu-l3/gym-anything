#!/bin/bash
set -euo pipefail

echo "=== Setting up walker_constellation_setup task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output
rm -f /home/ga/Desktop/constellation_pdr.txt

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Create PDR document
cat > /home/ga/Desktop/constellation_pdr.txt << 'PDREOF'
==========================================================
       TERRASCAN INC. — PRELIMINARY DESIGN REVIEW
       Constellation Architecture Specification
       Document: TSI-PDR-2025-003, Rev A
       Date: 15 Nov 2025
==========================================================

1. MISSION OVERVIEW

   TerraScan is a 6-satellite Earth observation constellation
   designed for sub-daily revisit of mid-latitude agricultural
   regions. The constellation shall provide complete coverage
   between 60°N and 60°S latitude with a maximum revisit gap
   of 6 hours.

2. CONSTELLATION PATTERN

   Walker-Delta:  6/3/1

   Notation:  t/p/f where
     t = 6   (total number of operational satellites)
     p = 3   (number of equally-spaced orbital planes)
     f = 1   (relative phasing between adjacent planes)

   Reference: Walker, J.G. (1984) "Satellite Constellations,"
   Journal of the British Interplanetary Society, Vol. 37, pp. 559-571.

3. ORBITAL PARAMETERS (all satellites identical)

   Semi-Major Axis:   7071.14 km  (700 km altitude)
   Eccentricity:      0.001
   Inclination:       98.19 deg   (sun-synchronous)
   Arg. of Perigee:   0.0 deg
   LTAN:              10:30 (descending node local time)

4. EPOCH

   Reference epoch:   01 Jan 2026 12:00:00.000 UTC

5. SPACECRAFT BUS

   Dry Mass:          85 kg (per satellite)
   Drag Area:         1.2 m^2
   Cd:                2.2
   SRP Area:          1.2 m^2
   Cr:                1.4

6. PROPAGATION REQUIREMENTS

   Force model must include at minimum:
   - Earth gravity (JGM-2 or JGM-3, degree/order >= 2)
   - Earth J2 effect is required for sun-synchronous simulation

7. DELIVERABLES

   The astrodynamics team shall produce:
   a) A GMAT mission script implementing all 6 satellites
   b) One-period propagation verification (~98.8 min)
   c) Geometry report confirming Walker pattern compliance

8. NAMING CONVENTION

   Satellites: TS_1A, TS_1B, TS_2A, TS_2B, TS_3A, TS_3B
   (Plane number followed by satellite letter within plane)

==========================================================
   APPROVED: Dr. R. Battin, Chief Architect
   CLASSIFICATION: UNCLASSIFIED / FOUO
==========================================================
PDREOF

chown ga:ga /home/ga/Desktop/constellation_pdr.txt

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
    
    # Capture initial state proving GMAT is open and document is available
    take_screenshot /tmp/task_initial_state.png
    echo "Initial screenshot captured."
else
    echo "ERROR: GMAT failed to start within timeout."
    exit 1
fi

echo "=== Task Setup Complete ==="