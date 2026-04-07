#!/bin/bash
set -e
echo "=== Setting up scenario_library_maintenance task ==="

BC_ROOT="/opt/bridgecommand"
SCENARIOS_DIR="$BC_ROOT/Scenarios"
MODELS_DIR="$BC_ROOT/Models"

# Ensure directories exist
mkdir -p "$SCENARIOS_DIR"
mkdir -p "$MODELS_DIR"

# 1. Setup Valid Models (Deterministic set)
# We ensure these exist so the agent sees them as "valid"
for model in "Coaster" "Ferry" "Tug" "Yacht"; do
    if [ ! -d "$MODELS_DIR/$model" ]; then
        mkdir -p "$MODELS_DIR/$model"
        # Create a dummy mesh file just in case agent checks file content (unlikely but safe)
        touch "$MODELS_DIR/$model/master.x"
    fi
done

# 2. Setup Scenarios
# We create specific scenarios to test each logic branch

# A. Fatal Scenario (Missing Ownship) -> Should go to Quarantine
SCEN_FATAL="$SCENARIOS_DIR/Legacy_Fatal_Error"
mkdir -p "$SCEN_FATAL"
cat > "$SCEN_FATAL/ownship.ini" << EOF
ShipName="Ghost_Ship_404"
InitialLat=50.8
InitialLong=-1.1
InitialHeading=090
InitialSpeed=10
EOF
cat > "$SCEN_FATAL/environment.ini" << EOF
Setting="Solent"
EOF
# No description.txt

# B. Repair Scenario (Missing Tug in Traffic) -> Should change to "Tug"
SCEN_TUG="$SCENARIOS_DIR/Legacy_Missing_Tug"
mkdir -p "$SCEN_TUG"
cat > "$SCEN_TUG/ownship.ini" << EOF
ShipName="Coaster"
EOF
cat > "$SCEN_TUG/othership.ini" << EOF
Number=2
Type(1)="Old_Steam_Tug_v1"
Name(1)="Tuggy"
Type(2)="Ferry"
Name(2)="ValidFerry"
EOF
cat > "$SCEN_TUG/environment.ini" << EOF
Setting="Solent"
EOF
# Missing description.txt

# C. Repair Scenario (Missing Generic in Traffic) -> Should change to "Coaster"
SCEN_GENERIC="$SCENARIOS_DIR/Legacy_Unknown_Ship"
mkdir -p "$SCEN_GENERIC"
cat > "$SCEN_GENERIC/ownship.ini" << EOF
ShipName="Yacht"
EOF
cat > "$SCEN_GENERIC/othership.ini" << EOF
Number=1
Type(1)="Mystery_Cargo_Vessel_2000"
Name(1)="Mystery"
EOF
cat > "$SCEN_GENERIC/environment.ini" << EOF
Setting="Solent"
EOF
echo "Original description" > "$SCEN_GENERIC/description.txt"

# D. Valid Scenario -> Should be untouched
SCEN_VALID="$SCENARIOS_DIR/Legacy_Valid_Archive"
mkdir -p "$SCEN_VALID"
cat > "$SCEN_VALID/ownship.ini" << EOF
ShipName="Ferry"
EOF
cat > "$SCEN_VALID/othership.ini" << EOF
Number=1
Type(1)="Coaster"
EOF
cat > "$SCEN_VALID/environment.ini" << EOF
Setting="Solent"
EOF
# Missing description.txt (needs one created)

# 3. Cleanup timestamps
date +%s > /tmp/task_start_time.txt
rm -rf /home/ga/Quarantine 2>/dev/null || true
rm -f /home/ga/Documents/audit_report.txt 2>/dev/null || true

# 4. Set permissions
chown -R ga:ga "$BC_ROOT"
chown -R ga:ga /home/ga

echo "=== Setup complete ==="
echo "Models available: Coaster, Ferry, Tug, Yacht"
echo "Scenarios seeded: Legacy_Fatal_Error, Legacy_Missing_Tug, Legacy_Unknown_Ship, Legacy_Valid_Archive"