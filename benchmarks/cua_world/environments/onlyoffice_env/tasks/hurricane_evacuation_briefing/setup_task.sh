#!/bin/bash
set -euo pipefail

echo "=== Setting up Hurricane Evacuation Briefing Task ==="

source /workspace/scripts/task_utils.sh

# Cleanup previous instances
cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create the working directory
PRES_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$PRES_DIR"

# 1. Create NHC Advisory Text (Real Historical Data)
cat > "$PRES_DIR/nhc_advisory_22.txt" << 'EOF'
BULLETIN
Hurricane Ian Advisory Number 22
NWS National Hurricane Center Miami FL       AL092022
1100 AM EDT Wed Sep 28 2022

...IAN LOCATED JUST OFFSHORE OF SOUTHWESTERN FLORIDA...
...CATASTROPHIC STORM SURGE, WINDS, AND FLOODING IN THE FLORIDA PENINSULA...

SUMMARY OF 1100 AM EDT...1500 UTC...INFORMATION
-----------------------------------------------
LOCATION...26.6N 82.3W
ABOUT 45 MI...70 KM WNW OF NAPLES FLORIDA
ABOUT 50 MI...80 KM SSW OF PUNTA GORDA FLORIDA
MAXIMUM SUSTAINED WINDS...155 MPH...250 KM/H
PRESENT MOVEMENT...NNE OR 15 DEGREES AT 9 MPH...15 KM/H
MINIMUM CENTRAL PRESSURE...936 MB...27.64 INCHES

STORM SURGE:
The combination of storm surge and the tide will cause normally dry areas near the coast to be flooded by rising waters moving inland from the shoreline. 
Englewood to Bonita Beach... 12-18 ft
Charlotte Harbor... 12-18 ft
Bonita Beach to Chokoloskee... 8-12 ft
EOF

# 2. Create County Response Plan
cat > "$PRES_DIR/county_response_plan.txt" << 'EOF'
COASTAL COUNTY EMA - HURRICANE RESPONSE PLAN
Activation Level: 1 (FULL)

EVACUATION ORDERS:
Mandatory Evacuations are currently in effect for:
- Zone A (Coastal and low-lying barrier islands)
- Zone B (Areas prone to storm surge and all mobile homes)
Voluntary Evacuations are recommended for Zone C.

SHELTER OPERATIONS:
The following emergency shelters are officially OPEN:
1. Coastal County High School (General Population / Pet Friendly)
2. Downtown Civic Center (Special Needs Medical Shelter)

CRITICAL LIFE SAFETY PROTOCOL:
Emergency services (Police, Fire, EMS) will suspend all response operations when sustained winds reach or exceed 45 mph. Residents must shelter in place after this threshold is met.
EOF

# 3. Create realistic graphic placeholders using ImageMagick
echo "Generating threat graphics..."
su - ga -c "convert -size 1024x768 gradient:blue-white -pointsize 48 -font Liberation-Sans-Bold -gravity center -annotate +0-50 'HURRICANE IAN' -pointsize 36 -fill darkred -annotate +0+50 'OFFICIAL NHC FORECAST TRACK' '$PRES_DIR/ian_track_cone.png'"
su - ga -c "convert -size 1024x768 gradient:red-yellow -pointsize 48 -font Liberation-Sans-Bold -gravity center -annotate +0-50 'PEAK STORM SURGE' -pointsize 36 -fill black -annotate +0+50 '12-18 FEET (Englewood to Bonita Beach)' '$PRES_DIR/ian_storm_surge.png'"

chown -R ga:ga "$PRES_DIR"

# Launch ONLYOFFICE Presentation Editor directly
echo "Launching ONLYOFFICE Presentation Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:slide > /tmp/onlyoffice.log 2>&1 &"

# Wait for it to appear
wait_for_window "ONLYOFFICE" 30
sleep 3

# Maximize and Focus
focus_onlyoffice_window || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="