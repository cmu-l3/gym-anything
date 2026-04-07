#!/bin/bash
set -e
echo "=== Setting up AIS Traffic Conversion Task ==="

# Define paths
DOCS_DIR="/home/ga/Documents/ais_data"
CSV_FILE="$DOCS_DIR/solent_traffic_20231015.csv"
README_FILE="$DOCS_DIR/README.txt"
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
BC_DATA="/opt/bridgecommand"

# Create directories
mkdir -p "$DOCS_DIR"
mkdir -p "$BC_CONFIG_DIR"

# Clean previous task artifacts
rm -rf "$BC_DATA/Scenarios/p) Solent AIS Traffic 20231015" 2>/dev/null || true
rm -f "$DOCS_DIR/conversion_report.txt" 2>/dev/null || true

# Reset bc5.ini to defaults (to ensure agent actually changes it)
cat > "$BC_CONFIG_DIR/bc5.ini" << EOF
[Graphics]
view_angle=90
[RADAR]
arpa_on=0
full_radar=0
max_radar_range=48
radar_range_resolution=128
[Startup]
EOF
chown -R ga:ga "$BC_CONFIG_DIR"
# Also copy to data dir as BC reads both
cp "$BC_CONFIG_DIR/bc5.ini" "$BC_DATA/bc5.ini" 2>/dev/null || true

# Generate Realistic AIS Data CSV
# Format: MMSI,VesselName,VesselType,Latitude,Longitude,SOG_kts,COG,Heading,Timestamp,NavStatus
cat > "$CSV_FILE" << EOF
MMSI,VesselName,VesselType,Latitude,Longitude,SOG_kts,COG,Heading,Timestamp,NavStatus
235001234,EVER FORTUNE,Container Ship,50.7700,-1.0500,14.2,315,315,2023-10-15T14:00:00Z,Under way using engine
235001234,EVER FORTUNE,Container Ship,50.7750,-1.0600,14.0,315,315,2023-10-15T14:05:00Z,Under way using engine
235001234,EVER FORTUNE,Container Ship,50.7800,-1.0700,13.8,310,310,2023-10-15T14:10:00Z,Under way using engine
235067890,RED OSPREY,Ro-Ro Cargo,50.7600,-1.2800,12.5,045,045,2023-10-15T14:00:00Z,Under way using engine
235067890,RED OSPREY,Ro-Ro Cargo,50.7650,-1.2750,12.5,045,045,2023-10-15T14:05:00Z,Under way using engine
235067890,RED OSPREY,Ro-Ro Cargo,50.7700,-1.2700,12.0,050,050,2023-10-15T14:10:00Z,Under way using engine
244012345,WHITCHALLENGER,Crude Oil Tanker,50.8000,-1.1000,10.0,290,290,2023-10-15T14:00:00Z,Under way using engine
244012345,WHITCHALLENGER,Crude Oil Tanker,50.8050,-1.1200,9.8,290,290,2023-10-15T14:10:00Z,Under way using engine
235098765,RED JET 7,High-Speed Craft,50.8500,-1.2000,32.0,180,180,2023-10-15T14:00:00Z,Under way using engine
235098765,RED JET 7,High-Speed Craft,50.8300,-1.2000,32.5,180,180,2023-10-15T14:05:00Z,Under way using engine
232001456,SOLENT PILOT,Pilot Vessel,50.7500,-1.0200,18.0,270,270,2023-10-15T14:00:00Z,Under way using engine
232001456,SOLENT PILOT,Pilot Vessel,50.7500,-1.0400,18.0,270,270,2023-10-15T14:05:00Z,Under way using engine
235555123,MISCHIEF,Sailing Vessel,50.7200,-1.4000,6.0,090,090,2023-10-15T14:00:00Z,Under way using engine
235555123,MISCHIEF,Sailing Vessel,50.7200,-1.3900,6.1,090,090,2023-10-15T14:10:00Z,Under way using engine
538004321,GRAND PIONEER,Bulk Carrier,50.8200,-1.3000,11.5,135,135,2023-10-15T14:00:00Z,Under way using engine
538004321,GRAND PIONEER,Bulk Carrier,50.8100,-1.2900,11.5,135,135,2023-10-15T14:10:00Z,Under way using engine
232005789,COASTGUARD ECHO,Search and Rescue,50.7900,-1.1500,20.0,000,000,2023-10-15T14:00:00Z,Under way using engine
232005789,COASTGUARD ECHO,Search and Rescue,50.8000,-1.1500,20.0,000,000,2023-10-15T14:05:00Z,Under way using engine
EOF

# Create README
cat > "$README_FILE" << EOF
AIS Data Conversion Task
========================

The file 'solent_traffic_20231015.csv' contains raw AIS position reports for 8 vessels.
Your task is to convert this data into a Bridge Command scenario.

1. Parse the CSV.
2. Calculate relative movements for waypoint legs.
3. Create the scenario in /opt/bridgecommand/Scenarios/.
4. Update your radar settings.

See the task description for full details.
EOF

# Set permissions
chown -R ga:ga "$DOCS_DIR"

# Ensure Bridge Command is NOT running (agent should focus on file creation first)
pkill -f "bridgecommand" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Initial screenshot (desktop state)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="