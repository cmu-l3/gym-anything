#!/bin/bash
echo "=== Setting up collision_avoidance_investigation task ==="

# Define paths
BC_DATA="/opt/bridgecommand"
RECON_DIR="$BC_DATA/Scenarios/n) Collision Reconstruction"
AVOID_DIR="$BC_DATA/Scenarios/o) Avoidance Demonstration"
INVEST_DIR="/home/ga/Documents/Investigation"
REPORT_FILE="$INVEST_DIR/collision_report.txt"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="$BC_DATA/bc5.ini"

# 1. Clean up previous artifacts BEFORE recording timestamp
echo "Cleaning up previous task artifacts..."
rm -rf "$RECON_DIR" 2>/dev/null || true
rm -rf "$AVOID_DIR" 2>/dev/null || true
rm -rf "$INVEST_DIR" 2>/dev/null || true

# 2. Record task start time (AFTER cleanup, BEFORE data creation)
date +%s > /tmp/task_start_time.txt

# 3. Create investigation data directory
mkdir -p "$INVEST_DIR"
chown ga:ga "$INVEST_DIR"

# 4. Write VDR data for Ship A — MV Pacific Grace (northbound container ship)
# 6 position reports at 3-minute intervals, heading 000 at 12 knots
# At latitude ~50.7, 12 kts = 0.2 deg/hr northward = 0.01 deg per 3 min
cat > "$INVEST_DIR/vessel_a_vdr.csv" << 'VDR_A_EOF'
Timestamp_UTC,Lat,Lon,COG,SOG
13:45:00,50.6967,-0.9700,000.0,12.0
13:48:00,50.7067,-0.9700,000.0,12.0
13:51:00,50.7167,-0.9700,000.0,12.0
13:54:00,50.7267,-0.9700,000.0,12.0
13:57:00,50.7367,-0.9700,000.0,12.0
14:00:00,50.7467,-0.9700,000.0,12.0
VDR_A_EOF

# 5. Write VDR data for Ship B — MT Solent Star (westbound tanker)
# 6 position reports at 3-minute intervals, heading 270 at 8 knots
# At lat 50.78, 1 deg lon = 38.01 nm, so 8 kts = 0.01053 deg/3min westward
cat > "$INVEST_DIR/vessel_b_vdr.csv" << 'VDR_B_EOF'
Timestamp_UTC,Lat,Lon,COG,SOG
13:45:00,50.7800,-0.8823,270.0,8.0
13:48:00,50.7800,-0.8928,270.0,8.0
13:51:00,50.7800,-0.9033,270.0,8.0
13:54:00,50.7800,-0.9138,270.0,8.0
13:57:00,50.7800,-0.9244,270.0,8.0
14:00:00,50.7800,-0.9349,270.0,8.0
VDR_B_EOF

# 6. Write VTS traffic snapshot — positions of other vessels at 14:00 UTC
cat > "$INVEST_DIR/vts_traffic_snapshot.csv" << 'VTS_EOF'
Vessel_Name,Lat,Lon,COG,SOG,Type
HSC Solent Express,50.7900,-0.9600,180.0,15.0,High Speed Craft
FV Morning Catch,50.7550,-0.9350,315.0,5.0,Fishing Vessel
VTS_EOF

# 7. Write weather conditions report
cat > "$INVEST_DIR/weather_conditions.txt" << 'WX_EOF'
================================================================
MARITIME WEATHER REPORT - SOLENT AREA
Date: 15 November 2024, 14:00 UTC
================================================================

Visibility:    8.0 nautical miles
Wind:          Southwest 220 degrees, 15 knots (Beaufort Force 4)
Sea State:     Moderate (3.0)
Rain:          None
Cloud Cover:   Overcast (8/8)
Pressure:      1008 hPa, falling slowly

Sunrise:       07:15 UTC
Sunset:        16:30 UTC
Variation:     -1.5 degrees (West)

Comments: Daylight conditions. Good visibility throughout.
          Moderate swell from southwest.
================================================================
WX_EOF

# Set ownership on all investigation files
chown -R ga:ga "$INVEST_DIR"

# 8. Reset Bridge Command configuration to defaults (disable ARPA/Radar)
echo "Resetting bc5.ini configuration..."
mkdir -p "$(dirname "$BC_CONFIG_USER")"

cat > /tmp/bc5_default.ini << 'BC5_EOF'
[Graphics]
view_angle=90
[RADAR]
arpa_on=0
full_radar=0
max_radar_range=48
radar_range_resolution=128
[Startup]
BC5_EOF

cp /tmp/bc5_default.ini "$BC_CONFIG_USER"
cp /tmp/bc5_default.ini "$BC_CONFIG_DATA" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config"

# 9. Kill any running Bridge Command instances
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

# 10. Launch Bridge Command Launcher
echo "Starting Bridge Command..."
if ! pgrep -f "bridgecommand" > /dev/null; then
    su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_launch.log 2>&1 &"
    sleep 5
fi

# 11. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Bridge Command window detected"
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Bridge Command" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# 12. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
