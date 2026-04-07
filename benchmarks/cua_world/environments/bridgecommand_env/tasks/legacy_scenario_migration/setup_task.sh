#!/bin/bash
set -e
echo "=== Setting up Legacy Scenario Migration Task ==="

# Define paths
DOCS_DIR="/home/ga/Documents"
LEGACY_DIR="$DOCS_DIR/legacy_scenarios"
SPEC_FILE="$DOCS_DIR/migration_spec.txt"
BC_SCENARIOS="/opt/bridgecommand/Scenarios"

# Create directories
mkdir -p "$LEGACY_DIR"
chown ga:ga "$DOCS_DIR"
chown ga:ga "$LEGACY_DIR"

# Clean up any previous run artifacts in the target directory
rm -rf "$BC_SCENARIOS/Migrated - "* 2>/dev/null || true

# --- Create Legacy Scenario A ---
mkdir -p "$LEGACY_DIR/Scenario_A"
cat > "$LEGACY_DIR/Scenario_A/environment.ini" << EOF
Setting="Solent"
StartTime=12.0
VisibilityRange=10.0
Weather=1.0
EOF

cat > "$LEGACY_DIR/Scenario_A/ownship.ini" << EOF
ShipName="OwnShip_A"
InitialLat=50.8000
InitialLong=-1.1000
InitialHeading=090
InitialSpeed=10.0
EOF

cat > "$LEGACY_DIR/Scenario_A/othership.ini" << EOF
Number=1
Type(1)="Old_Tanker"
InitLat(1)=50.8100
InitLong(1)=-1.1200
InitBearing(1)=270
InitSpeed(1)=12.0
Legs(1)=1
Leg(1,1)=270,12.0,5.0
EOF

# --- Create Legacy Scenario B ---
mkdir -p "$LEGACY_DIR/Scenario_B"
cat > "$LEGACY_DIR/Scenario_B/environment.ini" << EOF
Setting="English Channel"
StartTime=14.0
VisibilityRange=5.0
Weather=3.0
EOF

cat > "$LEGACY_DIR/Scenario_B/ownship.ini" << EOF
ShipName="OwnShip_B"
InitialLat=50.5000
InitialLong=-0.5000
InitialHeading=180
InitialSpeed=15.0
EOF

cat > "$LEGACY_DIR/Scenario_B/othership.ini" << EOF
Number=1
Type(1)="Old_Ferry"
InitLat(1)=50.5100
InitLong(1)=-0.5100
InitBearing(1)=000
InitSpeed(1)=18.0
Legs(1)=1
Leg(1,1)=000,18.0,10.0
EOF

# --- Create Legacy Scenario C ---
mkdir -p "$LEGACY_DIR/Scenario_C"
cat > "$LEGACY_DIR/Scenario_C/environment.ini" << EOF
Setting="Plymouth"
StartTime=08.0
VisibilityRange=2.0
Weather=0.0
EOF

cat > "$LEGACY_DIR/Scenario_C/ownship.ini" << EOF
ShipName="OwnShip_C"
InitialLat=50.2000
InitialLong=-1.5000
InitialHeading=270
InitialSpeed=5.0
EOF

cat > "$LEGACY_DIR/Scenario_C/othership.ini" << EOF
Number=1
Type(1)="Old_Buoy"
InitLat(1)=50.2050
InitLong(1)=-1.5050
InitBearing(1)=000
InitSpeed(1)=0.0
Legs(1)=0
EOF

# --- Create Migration Spec ---
cat > "$SPEC_FILE" << EOF
MIGRATION SPECIFICATION v1.2
============================

1. COORDINATE DATUM SHIFT
   Due to a projection error in the legacy dataset (ED50 vs WGS84), all coordinates must be shifted.
   
   Latitude Adjustment:  +0.0015
   Longitude Adjustment: -0.0022
   
   Apply this to:
   - ownship.ini: InitialLat, InitialLong
   - othership.ini: InitLat(N), InitLong(N)

2. MODEL DEPRECATION MAP
   The following 3D models have been removed from the asset library. Replace them with modern equivalents:
   
   Legacy Model ID   |   Target Model ID
   ------------------|-------------------
   Old_Tanker        |   Tanker_A
   Old_Ferry         |   Ferry_Pax_1
   Old_Buoy          |   Buoy_Cardinal_N

3. OUTPUT DIRECTORY
   Save migrated scenarios to /opt/bridgecommand/Scenarios/
   Prefix folder names with "Migrated - "
EOF

# Set permissions
chown -R ga:ga "$LEGACY_DIR"
chown ga:ga "$SPEC_FILE"

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch a file manager to show the documents (helpful context)
su - ga -c "DISPLAY=:1 pcmanfm /home/ga/Documents &"

echo "=== Setup Complete ==="