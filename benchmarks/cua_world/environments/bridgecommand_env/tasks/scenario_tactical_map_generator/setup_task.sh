#!/bin/bash
set -e
echo "=== Setting up Tactical Map Generator Task ==="

# 1. Install dependencies (matplotlib is required for the task)
echo "Installing python dependencies..."
# Check if pip is available, install matplotlib
if command -v pip3 &> /dev/null; then
    pip3 install matplotlib configparser numpy > /dev/null 2>&1 || true
else
    apt-get update && apt-get install -y python3-matplotlib python3-numpy
fi

# 2. Setup the Public Test Scenario (Portsmouth Approach)
SCENARIO_DIR="/opt/bridgecommand/Scenarios/m) Portsmouth Approach Custom"
mkdir -p "$SCENARIO_DIR"

# Create environment.ini
cat > "$SCENARIO_DIR/environment.ini" << EOF
Setting=Solent
StartTime=10.0
VisibilityRange=10.0
EOF

# Create ownship.ini
cat > "$SCENARIO_DIR/ownship.ini" << EOF
ShipName=MV Target
InitialLat=50.79
InitialLong=-1.11
InitialBearing=180
InitialSpeed=10
EOF

# Create othership.ini (Complex formatting to test parsing)
cat > "$SCENARIO_DIR/othership.ini" << EOF
Number=2
Name(0)=Incoming Tanker
InitialLat(0)=50.78
InitialLong(0)=-1.11
InitialBearing(0)=000
InitialSpeed(0)=12

Name(1)=Crossing Ferry
InitialLat(1)=50.785
InitialLong(1)=-1.10
InitialBearing(1)=270
InitialSpeed(1)=15
EOF

# 3. Setup the HIDDEN Validation Scenario (Agent should not see this path, but verifier uses it)
HIDDEN_DIR="/opt/bridgecommand/Scenarios/VALIDATION_HIDDEN_SCENARIO"
mkdir -p "$HIDDEN_DIR"

cat > "$HIDDEN_DIR/ownship.ini" << EOF
ShipName=Secret Ownship
InitialLat=0.0
InitialLong=0.0
InitialBearing=0
EOF

cat > "$HIDDEN_DIR/othership.ini" << EOF
Number=2
Name(0)=Secret Traffic 1
InitialLat(0)=0.01
InitialLong(0)=0.01
InitialBearing(0)=90

Name(1)=Secret Traffic 2
InitialLat(1)=-0.01
InitialLong(1)=-0.01
InitialBearing(1)=270
EOF

# Ensure permissions
chown -R ga:ga "/opt/bridgecommand/Scenarios"

# 4. Clean up previous run artifacts
rm -f /home/ga/Desktop/generate_tactical_map.py
rm -f /home/ga/generate_tactical_map.py
rm -f /home/ga/tactical_map.png
rm -f /home/ga/Desktop/tactical_map.png

# 5. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="