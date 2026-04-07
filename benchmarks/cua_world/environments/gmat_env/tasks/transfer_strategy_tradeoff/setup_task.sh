#!/bin/bash
set -euo pipefail

echo "=== Setting up transfer_strategy_tradeoff task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/transfer_trade_study_requirements.txt
rm -rf /home/ga/Documents/missions/*
rm -rf /home/ga/GMAT_output/*
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the mission requirements document
cat > /home/ga/Desktop/transfer_trade_study_requirements.txt << 'REQEOF'
TRANSFER TRADE STUDY REQUIREMENTS
===================================
Project: GEOLINK-3 Communications Satellite
Date: 2025-06-15
Prepared by: Mission Analysis Division, SatOps Group

OBJECTIVE:
Compare Hohmann and bi-elliptic transfer strategies for orbit raising
from the initial parking orbit to the operational GEO slot.

PARKING ORBIT (Post-Launch Injection):
  Semi-Major Axis:  6671.14 km  (300 km altitude circular)
  Eccentricity:     0.0
  Inclination:      0.0 deg  (equatorial launch from Kourou)
  RAAN:             0.0 deg
  AOP:              0.0 deg
  True Anomaly:     0.0 deg
  Epoch:            01 Jul 2025 12:00:00.000 UTC

TARGET ORBIT (Geostationary):
  Semi-Major Axis:  42164.17 km
  Eccentricity:     < 0.001 (circular)
  Inclination:      0.0 deg

SPACECRAFT PARAMETERS:
  Dry Mass:         3500 kg
  Cd:               2.2
  Cr:               1.8
  DragArea:         20.0 m^2
  SRPArea:          25.0 m^2

BI-ELLIPTIC OPTION:
  The bi-elliptic transfer shall use an intermediate apogee of
  100,000 km radius from Earth center. This tests whether the
  higher intermediate apogee reduces total delta-V compared to
  the direct Hohmann approach.

REQUIRED DELIVERABLES:
  1. GMAT script(s) implementing both transfer strategies
  2. Total delta-V (km/s) for Hohmann transfer
  3. Total delta-V (km/s) for bi-elliptic transfer
  4. Transfer time (hours) for each strategy
  5. Recommendation: which strategy is more fuel-efficient
  6. Written report saved to ~/GMAT_output/transfer_trade_study.txt

REPORT FORMAT:
  The report must include these labeled fields:
    hohmann_total_deltav_km_s: <value>
    bielliptic_total_deltav_km_s: <value>
    hohmann_transfer_time_hours: <value>
    bielliptic_transfer_time_hours: <value>
    recommended_strategy: <Hohmann or Bi-Elliptic>
    deltav_savings_km_s: <value>
    orbit_ratio: <value>
REQEOF

chown ga:ga /home/ga/Desktop/transfer_trade_study_requirements.txt

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

echo "=== Task Setup Complete: Requirements doc at ~/Desktop/transfer_trade_study_requirements.txt ==="