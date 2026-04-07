#!/bin/bash
echo "=== Setting up topographic_pressure_fingerprint task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="topographic_pressure_fingerprint"
PRES_FILE="/home/ga/PanoplyData/pres.mon.ltm.nc"
SLP_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify both data files exist (from env installation)
if [ ! -f "$PRES_FILE" ]; then
    echo "ERROR: Surface pressure data file not found: $PRES_FILE"
    exit 1
fi
if [ ! -f "$SLP_FILE" ]; then
    echo "ERROR: Sea-level pressure data file not found: $SLP_FILE"
    exit 1
fi

echo "Data files verified: pres.mon.ltm.nc and slp.mon.ltm.nc"

# Clean up any pre-existing outputs and directories
rm -rf "/home/ga/Documents/PressureLecture"
rm -f /home/ga/Desktop/pressure_lecture_brief.txt
echo "Cleaned up pre-existing outputs."

# Record task start timestamp for anti-gaming
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the course preparation brief to the desktop
cat > /home/ga/Desktop/pressure_lecture_brief.txt << 'SPECEOF'
EARTH SCIENCE 201 — LECTURE PREPARATION BRIEF
=============================================

Module: "How Topography Shapes the Atmosphere"
Instructor: Prof. Geography
Course: Introduction to Physical Geography

TASK:
Prepare two comparative global pressure maps for the January climatology
lecture, plus explanatory notes for the teaching assistant.

DELIVERABLES (you must create ~/Documents/PressureLecture/ and save all to it):

1. surface_pressure_jan.png
   - Global map of SURFACE PRESSURE from pres.mon.ltm.nc
   - January climatology (first time step)
   - This map should dramatically show topographic features

2. sealevel_pressure_jan.png
   - Global map of SEA-LEVEL PRESSURE from slp.mon.ltm.nc
   - January climatology (first time step)
   - This map should show weather-scale pressure patterns

3. lecture_notes.txt — Structured notes with the following fields:
   FEATURE_1: [Name of the most prominent topographic feature in surface pressure]
   FEATURE_1_PRESSURE_HPA: [Approximate surface pressure in hPa over this feature]
   FEATURE_2: [Name of a second prominent topographic feature]
   FEATURE_2_PRESSURE_HPA: [Approximate surface pressure in hPa over this feature]
   FEATURE_3: [Name of a third identifiable topographic feature]
   SEALEVEL_MEAN_HPA: [Approximate global mean sea-level pressure in hPa]
   KEY_DIFFERENCE: [One paragraph explaining why the two maps look so different]

TEACHING NOTE:
The key pedagogical point is that surface pressure directly reflects
elevation — the higher the terrain, the less atmosphere above it, and
the lower the surface pressure. Sea-level pressure removes this
topographic signal by mathematically "reducing" pressure to sea level,
revealing synoptic weather patterns instead. Students should be able
to identify major mountain ranges and ice sheets from the surface
pressure map alone.

DATA FILES:
- ~/PanoplyData/pres.mon.ltm.nc (NCEP surface pressure, long-term mean)
- ~/PanoplyData/slp.mon.ltm.nc (NCEP sea-level pressure, long-term mean)

NOTE ON UNITS: Panoply displays NCEP pressure in Pascals (Pa). 100 Pa = 1 hPa.
Please convert values to hPa for the report.
SPECEOF

chown ga:ga /home/ga/Desktop/pressure_lecture_brief.txt
chmod 644 /home/ga/Desktop/pressure_lecture_brief.txt
echo "Lecture brief written to ~/Desktop/pressure_lecture_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply empty (no data pre-loaded, agent must open files themselves)
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 60
sleep 5

# Maximize Panoply
maximize_panoply
focus_panoply

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot showing clean state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="