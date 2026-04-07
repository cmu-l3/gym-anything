#!/bin/bash
echo "=== Setting up north_atlantic_maritime_slp_assessment task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="north_atlantic_maritime_slp_assessment"
DATA_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/MaritimeRouting"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SLP data file not found: $DATA_FILE"
    exit 1
fi
echo "SLP data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/slp_january.png"
rm -f "$OUTPUT_DIR/slp_july.png"
rm -f "$OUTPUT_DIR/routing_advisory.txt"
rm -f /home/ga/Desktop/shipping_route_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (crucial for anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/shipping_route_brief.txt << 'SPECEOF'
=================================================================
NORTH ATLANTIC VESSEL ROUTING SERVICE
Seasonal Storm Corridor Assessment — Analysis Request
=================================================================

FROM: Fleet Operations Manager, TransOcean Shipping Ltd.
TO: Maritime Weather Routing Analyst
DATE: Annual Planning Cycle
PRIORITY: HIGH

SUBJECT: Seasonal Pressure Pattern Analysis for North Atlantic
         Route Optimization (New York ↔ Southampton corridor)

REQUEST:
Our fleet operates 47 container vessels on the transatlantic
corridor between New York (40.7°N, 74.0°W) and Southampton
(50.9°N, 1.4°W). The Great Circle route passes near 55-60°N,
which our captains report as highly variable in winter weather.

We require a climatological assessment of sea level pressure
patterns over the North Atlantic basin for:
  (a) January — representing peak winter storm season
  (b) July — representing summer fair-weather season

Please provide:
1. SLP maps for both months showing pressure center locations
2. Identification of the primary winter low-pressure storm center
   and its approximate central pressure (in hPa)
3. Identification of the primary summer high-pressure center
   and its approximate central pressure (in hPa)
4. A routing recommendation: should winter transatlantic vessels
   divert SOUTHERN or NORTHERN relative to the Great Circle route?

DATASET: NCEP/NCAR Reanalysis surface SLP climatology
FILE: /home/ga/PanoplyData/slp.mon.ltm.nc
VARIABLE: slp (Sea Level Pressure; NOTE: stored in Pascals,
          convert to hPa by dividing by 100)

DELIVERABLES:
- Export January SLP plot to:
  ~/Documents/MaritimeRouting/slp_january.png
- Export July SLP plot to:
  ~/Documents/MaritimeRouting/slp_july.png
- Write routing advisory to:
  ~/Documents/MaritimeRouting/routing_advisory.txt

REPORT FORMAT (use these exact field labels):
  ANALYSIS_VARIABLE: Sea Level Pressure
  WINTER_MONTH: January
  SUMMER_MONTH: July
  ICELANDIC_LOW_SLP_HPA: [central pressure of the Icelandic Low in January, in hPa]
  BERMUDA_HIGH_SLP_HPA: [central pressure of the Bermuda/Azores High in July, in hPa]
  PRIMARY_WINTER_STORM_BASIN: [name of ocean basin with deepest winter cyclonic center]
  RECOMMENDED_WINTER_ROUTE: [SOUTHERN or NORTHERN]
  SEASONAL_CONTRAST: [1-2 sentences describing how the North Atlantic pressure pattern shifts]
  DATA_SOURCE: NCEP/NCAR Reanalysis

BACKGROUND:
The Icelandic Low is a semi-permanent low-pressure center located
near Iceland (60-65°N, 20-40°W) that deepens dramatically in winter,
generating persistent cyclonic storm tracks. The Bermuda (Azores)
High is a semi-permanent subtropical anticyclone (near 30-35°N) that
strengthens and expands northward in summer, creating fair weather.
Understanding the seasonal interplay between these two pressure
centers is critical for optimal route planning.
=================================================================
SPECEOF

chown ga:ga /home/ga/Desktop/shipping_route_brief.txt
chmod 644 /home/ga/Desktop/shipping_route_brief.txt
echo "Analysis brief written to ~/Desktop/shipping_route_brief.txt"

# Kill any existing Panoply instances for a clean state
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 2

# Launch Panoply with SLP data pre-loaded
echo "Launching Panoply with SLP data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' > /dev/null 2>&1 &"

# Wait for Panoply window to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "panoply"; then
        echo "Panoply window detected."
        break
    fi
    sleep 2
done

# Let Panoply fully initialize UI
sleep 8

# Dismiss any startup dialogs (like tips or updates)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize the main Panoply window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -i "panoply" | awk '{print $1}' | head -1)
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take an initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="