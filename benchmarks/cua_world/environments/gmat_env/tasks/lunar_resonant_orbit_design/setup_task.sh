#!/bin/bash
set -euo pipefail

echo "=== Setting up lunar_resonant_orbit_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/skysurvey_orbit_requirements.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write requirements document to Desktop
cat > /home/ga/Desktop/skysurvey_orbit_requirements.txt << 'REQEOF'
=== SkySurveyor Mission: Orbit Requirements Document ===
Mission: SkySurveyor Wide-Field UV Survey Telescope
Document: ORB-REQ-001 Rev A
Date: 2025-03-15

1. ORBIT TYPE
   2:1 lunar resonant orbit (P/2 resonance)
   Spacecraft orbital period = 1/2 × Moon's sidereal period
   Moon sidereal period: 27.3217 days
   Target spacecraft period: 13.6609 days

2. ORBIT GEOMETRY CONSTRAINTS
   - Perigee altitude: > 44,650 km (> 7 Earth radii from Earth center, Van Allen avoidance)
   - Apogee altitude: unconstrained (expected ~370,000 km)
   - Inclination: 28.5 deg (KSC launch latitude)
   - RAAN: 0.0 deg (unconstrained)
   - AOP: 90.0 deg (places apogee above ecliptic)
   - Epoch: 01 Jun 2025 12:00:00.000 UTC

3. SPACECRAFT PROPERTIES
   - Dry mass: 362 kg
   - Drag area: 0.0 m² (above atmosphere; drag negligible)
   - SRP area: 4.8 m²
   - Cr (SRP coefficient): 1.2
   - Cd (drag coefficient): 0.0

4. FORCE MODEL REQUIREMENTS
   - Earth gravity: 8x8 minimum (JGM-2 or JGM-3)
   - Lunar gravity: REQUIRED (point mass minimum; critical for resonance)
   - Solar gravity: REQUIRED (point mass; affects apogee significantly)
   - Solar radiation pressure: RECOMMENDED
   - Atmospheric drag: NOT REQUIRED

5. PROPAGATION REQUIREMENTS
   - Duration: 120 days minimum
   - Integrator: RungeKutta89 recommended, tolerance <= 1e-11
   - Coordinate system: EarthMJ2000Eq

6. STABILITY ACCEPTANCE CRITERIA
   - Orbital period must remain within 5% of 13.6609 days for full propagation
   - No Earth or Moon impact
   - Orbit must not escape Earth's Hill sphere

7. ORBITAL MECHANICS NOTES
   The 2:1 lunar resonance SMA is computed from Kepler's third law:
     T = 2π × sqrt(a³/μ_Earth)
   where T = 13.6609 days = 1,180,302 seconds, μ_Earth = 398600.4418 km³/s²
   
   Expected SMA: ~242,000-244,000 km
   Expected eccentricity: ~0.55
REQEOF

chown ga:ga /home/ga/Desktop/skysurvey_orbit_requirements.txt

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

echo "=== Task Setup Complete: Requirements at ~/Desktop/skysurvey_orbit_requirements.txt ==="