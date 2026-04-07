#!/bin/bash
set -euo pipefail

echo "=== Setting up uncontrolled_reentry_prediction task ==="

# Source environment utils if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Clean up previous artifacts
rm -f /home/ga/Desktop/ssa_bulletin_59001.txt
rm -f /home/ga/GMAT_output/reentry_sim.script
rm -f /home/ga/GMAT_output/reentry_prediction_report.txt
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Desktop /home/ga/GMAT_output

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create the real-world SSA bulletin data
cat > /home/ga/Desktop/ssa_bulletin_59001.txt << 'EOF'
====================================================================
         SPACE SITUATIONAL AWARENESS BULLETIN #2025-0501-A
                 UNCONTROLLED RE-ENTRY ADVISORY
====================================================================

OBJECT DESIGNATION:   CZ-5B R/B
NORAD CATALOG ID:     59001
INTL DESIGNATOR:      2025-031B
OBJECT TYPE:          Spent Rocket Body - Uncontrolled

REFERENCE EPOCH:      01 May 2025 12:00:00.000 UTCG

KEPLERIAN ELEMENTS (Earth Mean-J2000 Equator):
  Semi-major Axis (SMA):    6621.140 km
  Eccentricity (ECC):       0.0012
  Inclination (INC):        41.47 deg
  RAAN:                      118.35 deg
  Argument of Perigee (AOP): 267.80 deg
  True Anomaly (TA):         45.00 deg

DERIVED ORBITAL PARAMETERS:
  Perigee Altitude:  ~242 km
  Apogee Altitude:   ~258 km
  Orbital Period:    ~89.4 min

PHYSICAL CHARACTERISTICS:
  Dry Mass:            3200 kg
  Estimated Drag Area: 28.0 m^2
  Drag Coefficient Cd: 2.2
  SRP Area:            28.0 m^2
  SRP Coefficient Cr:  1.2

ATMOSPHERIC MODEL GUIDANCE:
  Use Jacchia-Roberts atmosphere model with F10.7 = 150
  (moderate solar activity, 81-day average)

RE-ENTRY THRESHOLD:   120 km geodetic altitude
====================================================================
EOF
chown ga:ga /home/ga/Desktop/ssa_bulletin_59001.txt

# Launch GMAT application
if type launch_gmat &>/dev/null; then
    echo "Launching GMAT via utility..."
    launch_gmat ""
    WID=$(wait_for_gmat_window 60)
    if [ -n "$WID" ]; then
        focus_gmat_window
        dismiss_gmat_dialogs
    fi
else
    echo "Launching GMAT directly..."
    su - ga -c "DISPLAY=:1 /opt/GMAT/bin/GMAT_Beta > /dev/null 2>&1 &"
    sleep 10
    DISPLAY=:1 wmctrl -r "GMAT" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "GMAT" 2>/dev/null || true
fi

# Initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup complete ==="