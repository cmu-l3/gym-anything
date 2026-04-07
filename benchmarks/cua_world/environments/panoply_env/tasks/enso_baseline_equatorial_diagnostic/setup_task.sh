#!/bin/bash
echo "=== Setting up enso_baseline_equatorial_diagnostic task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="enso_baseline_equatorial_diagnostic"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/ENSODiagnostic"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SST data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SST data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/tropical_pacific_sst_july.png"
rm -f "$OUTPUT_DIR/equatorial_sst_profile_july.png"
rm -f "$OUTPUT_DIR/enso_baseline_report.txt"
rm -f /home/ga/Desktop/enso_diagnostic_directive.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis directive to the desktop
cat > /home/ga/Desktop/enso_diagnostic_directive.txt << 'SPECEOF'
ENSO BASELINE DIAGNOSTIC — IRI SEASONAL FORECAST DIVISION
================================================================

FROM: Chief Analyst, IRI ENSO Prediction Unit
TO: Climate Services Analyst (you)
DATE: Current
PRIORITY: ROUTINE

SUBJECT: Establish July Climatological SST Baseline for ENSO Monitoring

DIRECTIVE:

As part of our seasonal forecast cycle, we need updated baseline
diagnostic materials for the equatorial Pacific SST structure.
These will serve as the reference state for anomaly computation
and ENSO phase determination.

REQUIRED DELIVERABLES:

1. SPATIAL MAP: A geo-mapped plot of July sea surface temperature
   covering the tropical Pacific basin.
   Save to: ~/Documents/ENSODiagnostic/tropical_pacific_sst_july.png

2. EQUATORIAL LINE PLOT: A line plot (NOT a spatial map) showing
   SST as a function of longitude along the equator (0°N or nearest
   available latitude). This is our primary ENSO diagnostic graphic.
   Save to: ~/Documents/ENSODiagnostic/equatorial_sst_profile_july.png

3. BASELINE REPORT: A structured text report identifying the key
   equatorial Pacific SST features.
   Save to: ~/Documents/ENSODiagnostic/enso_baseline_report.txt

   The report MUST include these fields (one per line, colon-separated):
   - ANALYSIS_MONTH: [month name]
   - WARM_POOL_SST_C: [West Pacific Warm Pool temperature in °C]
   - COLD_TONGUE_SST_C: [East Pacific Cold Tongue temperature in °C]
   - EQUATORIAL_SST_GRADIENT_C: [Warm Pool minus Cold Tongue, in °C]
   - NINO34_BASELINE_SST_C: [mean SST in 170°W-120°W, 5°S-5°N, in °C]
   - ENSO_PHASE: [EL_NINO, LA_NINA, or NEUTRAL]
   - PLOT_TYPE_USED: [describe what type of plot you created for deliverable 2]

SCIENTIFIC GUIDANCE:

- The dataset is a 1991-2020 LONG-TERM MEAN (climatology), not a
  single year's observation. Consider what this implies for ENSO
  phase classification.
- The West Pacific Warm Pool (120°E-180°) and East Pacific Cold
  Tongue (90°W-150°W) are the two defining features of equatorial
  Pacific SST structure.
- The Niño 3.4 region (170°W-120°W, 5°S-5°N) is the standard ENSO
  monitoring index region.
- July is when the Cold Tongue is well-developed due to seasonal
  intensification of equatorial upwelling.

DATA SOURCE: /home/ga/PanoplyData/sst.ltm.1991-2020.nc
VARIABLE: sst (Sea Surface Temperature, °C)
TIME STEP: July (index 6, 0-based)

================================================================
END OF DIRECTIVE
SPECEOF

chown ga:ga /home/ga/Desktop/enso_diagnostic_directive.txt
chmod 644 /home/ga/Desktop/enso_diagnostic_directive.txt
echo "Analysis directive written to ~/Desktop/enso_diagnostic_directive.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SST data pre-loaded
echo "Launching Panoply with SST data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Panoply Sources window
focus_panoply
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="