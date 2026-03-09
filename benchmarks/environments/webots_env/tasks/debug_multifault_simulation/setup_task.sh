#!/bin/bash
# Setup script for debug_multifault_simulation task
# Loads soccer.wbt and injects 3 distinct physics errors that the agent must discover and fix:
#   1. WorldInfo basicTimeStep = 256 (too slow for robot simulation)
#   2. WorldInfo gravity = 0.0 (zero gravity — non-physical)
#   3. BLUE_PLAYER_1 robot Physics mass = 0.0 (invalid — floating robot)

echo "=== Setting up debug_multifault_simulation task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 3

# Find the soccer world (known to exist from existing tasks)
DEMO_WORLD="$WEBOTS_HOME/projects/samples/demos/worlds/soccer.wbt"
if [ ! -f "$DEMO_WORLD" ]; then
    echo "Searching for soccer.wbt..."
    DEMO_WORLD=$(find "$WEBOTS_HOME" -name "soccer.wbt" -type f 2>/dev/null | head -1)
fi

if [ -z "$DEMO_WORLD" ] || [ ! -f "$DEMO_WORLD" ]; then
    echo "ERROR: soccer.wbt not found in Webots installation"
    exit 1
fi

echo "Found world: $DEMO_WORLD"

# Copy world and dependencies to writable location
USER_WORLD="/home/ga/webots_projects/debug_multifault_world.wbt"
mkdir -p /home/ga/webots_projects
cp "$DEMO_WORLD" "$USER_WORLD"

# Copy associated controllers and protos
DEMO_DIR="$(dirname "$(dirname "$DEMO_WORLD")")"
if [ -d "$DEMO_DIR/controllers" ]; then
    cp -r "$DEMO_DIR/controllers" /home/ga/webots_projects/ 2>/dev/null || true
fi
if [ -d "$DEMO_DIR/protos" ]; then
    cp -r "$DEMO_DIR/protos" /home/ga/webots_projects/ 2>/dev/null || true
fi
chown -R ga:ga /home/ga/webots_projects

# Verify baseline: confirm the world is a valid soccer world
if ! grep -q "basicTimeStep" "$USER_WORLD"; then
    echo "ERROR: World file doesn't contain basicTimeStep — unexpected format"
    exit 1
fi

# Inject Error 1: set basicTimeStep to 256 (way too slow for robot simulation)
echo "Injecting Error 1: setting basicTimeStep to 256..."
python3 -c "
import re, sys
with open('$USER_WORLD', 'r') as f:
    content = f.read()

# Replace basicTimeStep value
new_content = re.sub(r'basicTimeStep \d+', 'basicTimeStep 256', content)
if 'basicTimeStep 256' in new_content:
    print('  Error 1 injected: basicTimeStep = 256')
else:
    print('  WARNING: basicTimeStep replacement may have failed')

with open('$USER_WORLD', 'w') as f:
    f.write(new_content)
"

# Inject Error 2: set gravity to 0.0
echo "Injecting Error 2: setting gravity to 0.0..."
python3 -c "
import re
with open('$USER_WORLD', 'r') as f:
    content = f.read()

# Replace gravity value — match 'gravity X' or 'gravity X.XX'
new_content = re.sub(r'gravity [\d.]+', 'gravity 0.0', content)
if 'gravity 0.0' in new_content:
    print('  Error 2 injected: gravity = 0.0')
else:
    print('  INFO: gravity field not found, adding to WorldInfo...')
    # Add gravity to WorldInfo if not found
    new_content = re.sub(
        r'(WorldInfo \{)',
        r'\1\n  gravity 0.0',
        new_content,
        count=1
    )
    print('  Error 2 injected by insertion')

with open('$USER_WORLD', 'w') as f:
    f.write(new_content)
"

# Inject Error 3: find BLUE_PLAYER_1 robot and set its Physics mass to 0.0
# Strategy: find the DEF BLUE_PLAYER_1 block and modify or add Physics mass
echo "Injecting Error 3: setting BLUE_PLAYER_1 mass to 0.0..."
python3 -c "
import re

with open('$USER_WORLD', 'r') as f:
    content = f.read()

# Find BLUE_PLAYER_1 definition and inject/replace mass
# First check if there is a BLUE_PLAYER_1 DEF
if 'BLUE_PLAYER_1' not in content and 'SoccerPlayer' not in content:
    print('  WARNING: BLUE_PLAYER_1 or SoccerPlayer not found in world')
    # Try to patch any robot's Physics mass instead
    new_content = re.sub(
        r'(physics Physics \{[^}]*?)(density -1\n\s*)',
        r'\1density -1\n    mass 0.0\n    ',
        content,
        count=1,
        flags=re.DOTALL
    )
    if new_content != content:
        print('  Error 3 injected into first robot Physics node')
else:
    # Find the first Physics block after BLUE_PLAYER_1 (or in any robot) and set mass to 0.0
    # Approach: look for 'physics Physics {' block and add/replace mass
    # This regex finds physics blocks that already have a mass field and changes first one
    modified = False

    # Pattern: find mass field anywhere and change first occurrence to 0.0
    # that appears after BLUE_PLAYER_1
    blue_pos = content.find('BLUE_PLAYER_1')
    if blue_pos == -1:
        blue_pos = 0

    # Find next Physics block after BLUE_PLAYER_1
    physics_start = content.find('physics Physics {', blue_pos)
    if physics_start == -1:
        physics_start = content.find('Physics {', blue_pos)

    if physics_start != -1:
        # Find the closing brace of this Physics block
        depth = 0
        i = physics_start
        while i < len(content):
            if content[i] == '{':
                depth += 1
            elif content[i] == '}':
                depth -= 1
                if depth == 0:
                    physics_end = i
                    break
            i += 1

        physics_block = content[physics_start:physics_end+1]

        if 'mass' in physics_block:
            # Replace existing mass value
            new_physics = re.sub(r'mass [\d.]+', 'mass 0.0', physics_block, count=1)
        else:
            # Add mass 0.0 to physics block
            new_physics = physics_block.replace('{', '{\n    mass 0.0', 1)

        new_content = content[:physics_start] + new_physics + content[physics_end+1:]
        print('  Error 3 injected: first robot Physics mass = 0.0')
        modified = True

    if not modified:
        new_content = content
        print('  WARNING: Could not find Physics block to inject error 3')

with open('$USER_WORLD', 'w') as f:
    f.write(new_content)
"

# Verify all errors were injected
echo "Verifying error injection..."
grep "basicTimeStep" "$USER_WORLD" | head -1
grep "gravity" "$USER_WORLD" | head -1
grep "mass" "$USER_WORLD" | head -3

# Record the start timestamp and baseline
date +%s > /tmp/task_start_timestamp
echo "errors_injected: basicTimeStep=256, gravity=0.0, mass=0.0" > /tmp/debug_simulation_baseline

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/fixed_simulation.wbt

# Launch Webots with the broken world
echo "Launching Webots with broken world (3 errors seeded)..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded with 3 planted errors:"
echo "  1. basicTimeStep = 256 (should be <= 64)"
echo "  2. gravity = 0.0 (should be ~9.81)"
echo "  3. First robot Physics mass = 0.0 (should be > 0)"
echo "Agent must discover and fix all errors, then save to /home/ga/Desktop/fixed_simulation.wbt"
