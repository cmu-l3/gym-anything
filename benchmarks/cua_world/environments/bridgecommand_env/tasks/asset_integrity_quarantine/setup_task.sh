#!/bin/bash
set -e
echo "=== Setting up Asset Integrity Quarantine Task ==="

# Define paths
BC_MODELS="/opt/bridgecommand/Models"
OWNSHIP_DIR="$BC_MODELS/Ownship"
OTHER_DIR="$BC_MODELS/Other"
LOG_FILE="/home/ga/Documents/bc_startup_errors.log"

# Ensure directories exist
mkdir -p "$OWNSHIP_DIR"
mkdir -p "$OTHER_DIR"
mkdir -p "/home/ga/Documents"

# --- Create GOOD Assets (Should NOT be moved) ---

# 1. ValidShip (Folder based)
mkdir -p "$OWNSHIP_DIR/ValidShip"
touch "$OWNSHIP_DIR/ValidShip/ValidShip.x"
touch "$OWNSHIP_DIR/ValidShip/ValidShip.ini"
touch "$OWNSHIP_DIR/ValidShip/texture.png"

# 2. GoodBuoy (Loose files)
touch "$OTHER_DIR/GoodBuoy.x"
touch "$OTHER_DIR/GoodBuoy.ini"
touch "$OTHER_DIR/GoodBuoy_Map.png"


# --- Create BAD Assets (Must be moved) ---

# 1. BadShip_v1 (Loose files in Ownship) - Error: Mesh version
touch "$OWNSHIP_DIR/BadShip_v1.x"
touch "$OWNSHIP_DIR/BadShip_v1.ini"
touch "$OWNSHIP_DIR/BadShip_v1_diffuse.png"

# 2. RustyBuoy (Folder in Other) - Error: Texture missing
mkdir -p "$OTHER_DIR/RustyBuoy"
touch "$OTHER_DIR/RustyBuoy/RustyBuoy.x"
touch "$OTHER_DIR/RustyBuoy/RustyBuoy.ini"
# Missing texture file is the simulated error, but we create the folder/mesh/ini

# 3. CorruptTankerC (Loose files in Ownship) - Error: Parsing failed
touch "$OWNSHIP_DIR/CorruptTankerC.x"
touch "$OWNSHIP_DIR/CorruptTankerC.ini"

# Set permissions so agent can move them (simulating user-installed mods)
chown -R ga:ga "$BC_MODELS"
chmod -R 755 "$BC_MODELS"

# --- Generate Log File ---
cat > "$LOG_FILE" << 'EOF'
Bridge Command 5.7.2 Log
========================
[INFO]  10:00:01 : Root created.
[INFO]  10:00:01 : Loading library 'RenderSystem_GL'
[INFO]  10:00:02 : Initialising resource groups
[INFO]  10:00:02 : Parsing scripts for resource group Autodetect
[INFO]  10:00:02 : Finished parsing scripts for resource group Autodetect
[INFO]  10:00:03 : Loading Model: ValidShip... OK.
[INFO]  10:00:03 : Loading Model: GoodBuoy... OK.
[ERROR] 10:00:04 : ResourceManager: Unable to load 'BadShip_v1.x'. Mesh serializer version 1.40 is too old. Upgrade your tools.
[WARN]  10:00:04 : Fallback mesh not found for BadShip_v1.
[INFO]  10:00:05 : Loading Model: Harbour_Tug... OK.
[ERROR] 10:00:06 : Exception: Texture 'RustyBuoy_Rust.jpg' not found in path. Loading asset 'RustyBuoy' failed.
[INFO]  10:00:07 : Loading Environment: Solent... OK.
[ERROR] 10:00:08 : ScriptParser: Fatal error parsing 'CorruptTankerC.ini' at line 42. Unexpected token '<<<'.
[INFO]  10:00:09 : System initialisation complete with 3 errors.
EOF

chown ga:ga "$LOG_FILE"

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="
echo "Log file created at $LOG_FILE"
echo "Assets deployed to $BC_MODELS"