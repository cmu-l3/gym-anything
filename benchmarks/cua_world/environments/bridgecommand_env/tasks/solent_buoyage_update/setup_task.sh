#!/bin/bash
set -e
echo "=== Setting up Solent Buoyage Update Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Ensure the base Solent world exists
WORLD_DIR="/opt/bridgecommand/World"
SOLENT_SOURCE=""

# Find the Solent world (could be "m) Solent" or just "Solent")
if [ -d "$WORLD_DIR/m) Solent" ]; then
    SOLENT_SOURCE="$WORLD_DIR/m) Solent"
elif [ -d "$WORLD_DIR/Solent" ]; then
    SOLENT_SOURCE="$WORLD_DIR/Solent"
else
    # Create a dummy Solent world if missing (fallback for robust testing)
    echo "WARNING: Solent world not found. Creating dummy base world."
    SOLENT_SOURCE="$WORLD_DIR/Solent"
    mkdir -p "$SOLENT_SOURCE"
    
    # Create dummy buoy.ini
    cat > "$SOLENT_SOURCE/buoy.ini" <<EOF
Number=2
Type(1)="Port"
Long(1)=-1.1000
Lat(1)=50.7000
Type(2)="SafeWater"
Long(2)=-1.0878
Lat(2)=50.7588
EOF

    # Create dummy light.ini
    cat > "$SOLENT_SOURCE/light.ini" <<EOF
Number=1
Type(1)="White"
Range(1)=10
Sequence(1)="Iso.4s"
Long(1)=-1.0878
Lat(1)=50.7588
Height(1)=5
EOF

    # Create dummy description.ini
    cat > "$SOLENT_SOURCE/description.ini" <<EOF
Name="Solent"
EOF
fi

# Ensure permissions
chown -R ga:ga "$WORLD_DIR"

# 2. Generate Randomized Coordinates for the Task
# This prevents the agent from memorizing coordinates; it must read the file.

# Horse Sand Old Position (Real World approx)
# Decimal: 50.7588 N, -1.0878 W
# DMS: 50° 45.53' N, 01° 05.27' W
HS_OLD_LAT_DEG=50
HS_OLD_LAT_MIN=45.53
HS_OLD_LON_DEG=01
HS_OLD_LON_MIN=05.27
HS_OLD_LAT_DEC=50.7588
HS_OLD_LON_DEC=-1.0878

# Generate a random shift for the NEW position (0.2 to 0.5 nm South)
# bash random float logic
SHIFT=$(awk 'BEGIN {srand(); print 0.2 + (rand() * 0.3)}')
HS_NEW_LAT_MIN=$(echo "$HS_OLD_LAT_MIN - $SHIFT" | bc)
HS_NEW_LAT_DEC=$(echo "$HS_OLD_LAT_DEG + $HS_NEW_LAT_MIN / 60" | bc -l)

# Keep Longitude same for simplicity of calculation for the agent
HS_NEW_LON_MIN=$HS_OLD_LON_MIN
HS_NEW_LON_DEC=$HS_OLD_LON_DEC

# Wreck Position (0.8nm West of Old)
WRECK_LAT_MIN=$HS_OLD_LAT_MIN
WRECK_LON_MIN=$(echo "$HS_OLD_LON_MIN + 0.8" | bc)
WRECK_LAT_DEC=$HS_OLD_LAT_DEC
WRECK_LON_DEC=$(echo "-($HS_OLD_LON_DEG + $WRECK_LON_MIN / 60)" | bc -l)

# Format NTM strings (2 decimal places for minutes)
NTM_HS_NEW_LAT=$(printf "%.2f" $HS_NEW_LAT_MIN)
NTM_HS_NEW_LON=$(printf "%.2f" $HS_NEW_LON_MIN)
NTM_WRECK_LAT=$(printf "%.2f" $WRECK_LAT_MIN)
NTM_WRECK_LON=$(printf "%.2f" $WRECK_LON_MIN)

# Save Ground Truth (Hidden from agent)
mkdir -p /var/lib/bridgecommand/task_data
cat > /var/lib/bridgecommand/task_data/ground_truth.json <<EOF
{
    "hs_old_lat": $HS_OLD_LAT_DEC,
    "hs_old_lon": $HS_OLD_LON_DEC,
    "hs_new_lat": $HS_NEW_LAT_DEC,
    "hs_new_lon": $HS_NEW_LON_DEC,
    "wreck_lat": $WRECK_LAT_DEC,
    "wreck_lon": $WRECK_LON_DEC,
    "ntm_hs_lat_str": "$HS_OLD_LAT_DEG $NTM_HS_NEW_LAT",
    "ntm_hs_lon_str": "$HS_OLD_LON_DEG $NTM_HS_NEW_LON"
}
EOF
chmod 700 /var/lib/bridgecommand/task_data
chmod 700 /var/lib/bridgecommand

# 3. Create Notice to Mariners Document
DOC_PATH="/home/ga/Documents/NTM_12_26.txt"
mkdir -p /home/ga/Documents

cat > "$DOC_PATH" <<EOF
NOTICE TO MARINERS
No. 12 of 2026

SOLENT - EASTERN APPROACHES - BUOYAGE CHANGES

1. Mariners are advised that due to recent shifts in the Horse Sand bank, the Horse Sand Buoy has been permanently relocated.
   
   Buoy: Horse Sand (Safe Water Mark)
   Old Position: $HS_OLD_LAT_DEG° $HS_OLD_LAT_MIN' N, $HS_OLD_LON_DEG° $HS_OLD_LON_MIN' W
   NEW POSITION: $HS_OLD_LAT_DEG° $NTM_HS_NEW_LAT' N, $HS_OLD_LON_DEG° $NTM_HS_NEW_LON' W

2. A dangerous wreck has been identified approximately 0.8 nautical miles west of the bank. A new temporary Wreck marking buoy has been established.

   Buoy: Wreck (Unlit)
   Position: $HS_OLD_LAT_DEG° $NTM_WRECK_LAT' N, $HS_OLD_LON_DEG° $NTM_WRECK_LON' W
   Description: Standard Emergency Wreck Marking Buoy (Blue/Yellow stripes)

3. Simulator technicians are requested to update the "Solent" world model immediately. 
   Please create a new revision "Solent_v2026" to reflect these changes.

Authority: Queen's Harbour Master Portsmouth
Date: 15 March 2026
EOF

chown -R ga:ga /home/ga/Documents

# 4. Clean up any previous attempt
rm -rf "$WORLD_DIR/Solent_v2026" 2>/dev/null || true

# 5. Initial Screenshot
DISPLAY=:1 wmctrl -r "Bridge Command" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="