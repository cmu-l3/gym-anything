#!/bin/bash
echo "=== Setting up pilot_card_from_model task ==="

BC_DATA="/opt/bridgecommand"
DOCS_DIR="/home/ga/Documents"
SCENARIO_DIR="$BC_DATA/Scenarios/p) Solent Pilotage Approach"

# 1. Clean up previous run artifacts
rm -f "$DOCS_DIR/pilot_card.txt"
rm -rf "$SCENARIO_DIR"
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 2. Reset bc5.ini to a state where instruments might be hidden (to test if agent fixes it)
# We set hide_instruments=1 initially.
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="$BC_DATA/bc5.ini"

mkdir -p "$(dirname "$BC_CONFIG_USER")"

# Start with standard config
cp /workspace/config/bc5.ini "$BC_CONFIG_USER"
# Modify to hide instruments
sed -i 's/hide_instruments=.*/hide_instruments=1/' "$BC_CONFIG_USER"
# Ensure data dir config matches
cp "$BC_CONFIG_USER" "$BC_CONFIG_DATA" 2>/dev/null || true

chown -R ga:ga "/home/ga/.config"

# 3. Ensure models are available (critical for this task)
if [ ! -d "$BC_DATA/Models" ]; then
    echo "ERROR: Models directory missing at $BC_DATA/Models"
    # Create dummy models if missing (fallback for testing without full install)
    mkdir -p "$BC_DATA/Models/Container Ship"
    cat > "$BC_DATA/Models/Container Ship/ownship.ini" << EOF
Length=280
Width=32
MaxSpeed=24
TurnRate=0.4
RudderMaxAngle=35
EOF
    mkdir -p "$BC_DATA/Models/Small Ferry"
    cat > "$BC_DATA/Models/Small Ferry/ownship.ini" << EOF
Length=80
Width=14
MaxSpeed=18
TurnRate=1.2
RudderMaxAngle=45
EOF
fi

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot (desktop state)
# Ensure no apps are running
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="