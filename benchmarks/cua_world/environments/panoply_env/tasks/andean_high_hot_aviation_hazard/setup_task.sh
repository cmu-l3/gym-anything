#!/bin/bash
echo "=== Setting up andean_high_hot_aviation_hazard task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="andean_high_hot_aviation_hazard"
PRES_FILE="/home/ga/PanoplyData/pres.mon.ltm.nc"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
SLP_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/AviationLogistics"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify all data files exist
for file in "$PRES_FILE" "$AIR_FILE" "$SLP_FILE"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Required data file not found: $file"
        exit 1
    fi
done
echo "Required data files verified."

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/andes_surface_pressure_jan.png"
rm -f "$OUTPUT_DIR/andes_air_temperature_jan.png"
rm -f "$OUTPUT_DIR/high_hot_advisory.txt"
rm -f /home/ga/Desktop/route_evaluation_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (Anti-Gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/route_evaluation_mandate.txt << 'SPECEOF'
LATAM CARGO AVIATION OPERATIONS
FLIGHT PERFORMANCE ENGINEERING — ROUTE EVALUATION MANDATE
==========================================================
Mandate ID: ENG-PERF-2024-JAN-008
Analyst Role: Aviation Performance Engineer
Route Network: Central Andes (Bogota, Quito, La Paz, Cusco)

MANDATE OVERVIEW
----------------
"High and Hot" operations severely degrade aircraft aerodynamic performance 
and engine thrust. For high-elevation Andean airports, operations during 
austral summer (January) present the most critical risk for runway overruns 
and impaired climb gradients. 

You must evaluate the climatological baseline for Density Altitude hazards
over the central Andes during January. This requires assessing BOTH the 
actual surface pressure (which drops exponentially with elevation) and the 
surface air temperature.

DATA REQUIREMENTS
-----------------
- Available Datasets (in ~/PanoplyData/):
  1. Surface Air Temperature (air.mon.ltm.nc)
  2. Surface Pressure (pres.mon.ltm.nc)
  *WARNING:* Do NOT use Sea Level Pressure (slp.mon.ltm.nc), as this 
  mathematically removes the topographic elevation effect which is the primary 
  driver of our high-altitude hazard!
  
- Target month: January (Time step index 0)
- Target region: South America / Andes (approx. 10°N to 30°S, 85°W to 55°W)
- Tool: NASA Panoply

REQUIRED ANALYSIS & DELIVERABLES
--------------------------------
Using Panoply, you must produce three deliverables. Save all outputs 
to: ~/Documents/AviationLogistics/

1. Andean Surface Pressure Map (January):
   Filename: andes_surface_pressure_jan.png
   (Zoom into South America, check the minimum pressure over the high Andes)

2. Andean Air Temperature Map (January):
   Filename: andes_air_temperature_jan.png
   (Zoom into South America)

3. High/Hot Performance Advisory:
   Filename: high_hot_advisory.txt
   
   Required fields (use EXACTLY these key names, one per line):
     ASSESSMENT_MONTH: January
     TARGET_REGION: Andes
     LOWEST_PRESSURE_HPA: [Extract the approximate lowest surface pressure over the high Andes in hPa. Note: Panoply displays NCEP pressure in Pascals (Pa). You MUST convert this to HectoPascals (hPa) for the advisory. 1 hPa = 100 Pa.]
     CRITICAL_AERODYNAMIC_FACTOR: Density Altitude
     PAYLOAD_RESTRICTION_REQUIRED: [YES or NO — Are payload restrictions strictly required for operations where pressure drops below 750 hPa?]

SUBMISSION DEADLINE: Immediate — Schedule planning relies on this assessment.
SPECEOF

chown ga:ga /home/ga/Desktop/route_evaluation_mandate.txt
chmod 644 /home/ga/Desktop/route_evaluation_mandate.txt
echo "Mandate written to ~/Desktop/route_evaluation_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply (empty state, agent must open files themselves)
echo "Launching NASA Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Panoply" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Panoply" 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="