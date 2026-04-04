#!/bin/bash
# Setup script for deploy_swarm_experiment task
# Loads soccer.wbt and injects 3 distinct swarm configuration errors:
#   1. All soccer player robot controllers = "soccer_player_broken" (wrong/non-existent)
#   2. All soccer player robots positioned at same overlapping coordinates
#   3. WorldInfo basicTimeStep = 128 (too slow for real-time soccer control)

echo "=== Setting up deploy_swarm_experiment task ==="

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
USER_WORLD="/home/ga/webots_projects/swarm_experiment_world.wbt"
mkdir -p /home/ga/webots_projects
cp "$DEMO_WORLD" "$USER_WORLD"

# Copy associated controllers and protos (agent needs to be able to see valid controllers)
DEMO_DIR="$(dirname "$(dirname "$DEMO_WORLD")")"
if [ -d "$DEMO_DIR/controllers" ]; then
    cp -r "$DEMO_DIR/controllers" /home/ga/webots_projects/ 2>/dev/null || true
    echo "Controllers available in /home/ga/webots_projects/controllers/"
    ls /home/ga/webots_projects/controllers/ 2>/dev/null || true
fi
if [ -d "$DEMO_DIR/protos" ]; then
    cp -r "$DEMO_DIR/protos" /home/ga/webots_projects/ 2>/dev/null || true
fi
chown -R ga:ga /home/ga/webots_projects

# Verify baseline
if ! grep -q "soccer_player" "$USER_WORLD"; then
    echo "WARNING: 'soccer_player' controller not found in original world"
fi

echo "Injecting swarm configuration errors..."

# Inject Error 1: change all soccer_player controllers to wrong name
# Also change supervisor to wrong name
python3 -c "
with open('$USER_WORLD', 'r') as f:
    content = f.read()

# Replace soccer player controller with broken version
new_content = content.replace('\"soccer_player\"', '\"soccer_player_broken\"')

# Count how many replacements were made
count = content.count('\"soccer_player\"')
new_count = new_content.count('\"soccer_player_broken\"')
print(f'  Error 1: Changed {count} soccer_player controller(s) to soccer_player_broken')

with open('$USER_WORLD', 'w') as f:
    f.write(new_content)
"

# Inject Error 2: set all BLUE and YELLOW player robots to same position
# Strategy: find SoccerPlayer or Robot translation fields and set them to overlap
python3 -c "
import re

with open('$USER_WORLD', 'r') as f:
    content = f.read()

# Find all DEF BLUE/YELLOW players and stack them at (0, 0, 0.1)
# Pattern: find translation lines right after DEF BLUE_PLAYER_N or YELLOW_PLAYER_N
lines = content.split('\n')
new_lines = []
i = 0
modified_count = 0
while i < len(lines):
    line = lines[i]
    # Check if previous context was a BLUE or YELLOW player DEF
    if 'BLUE_PLAYER' in line or 'YELLOW_PLAYER' in line:
        new_lines.append(line)
        # Look ahead for translation line within next 5 lines
        j = i + 1
        while j < min(i + 6, len(lines)):
            if lines[j].strip().startswith('translation ') and len(lines[j].strip().split()) == 4:
                # Replace this translation with overlapping position
                indent = len(lines[j]) - len(lines[j].lstrip())
                new_lines.append(' ' * indent + 'translation 0 0 0.1')
                modified_count += 1
                i = j
                break
            j += 1
        else:
            i += 1
        continue
    new_lines.append(line)
    i += 1

new_content = '\n'.join(new_lines)
print(f'  Error 2: Set {modified_count} robot positions to overlapping (0, 0, 0.1)')

with open('$USER_WORLD', 'w') as f:
    f.write(new_content)
"

# Inject Error 3: set basicTimeStep to 128
python3 -c "
import re
with open('$USER_WORLD', 'r') as f:
    content = f.read()

new_content = re.sub(r'basicTimeStep \d+', 'basicTimeStep 128', content)
if 'basicTimeStep 128' in new_content:
    print('  Error 3 injected: basicTimeStep = 128')
else:
    print('  WARNING: basicTimeStep replacement may have failed')

with open('$USER_WORLD', 'w') as f:
    f.write(new_content)
"

# Verify errors
echo "Verifying error injection:"
echo "  basicTimeStep:"
grep "basicTimeStep" "$USER_WORLD"
echo "  Controllers:"
grep "controller " "$USER_WORLD" | head -5
echo "  Robot positions (first few):"
python3 -c "
with open('$USER_WORLD') as f:
    content = f.read()
import re
players = ['BLUE_PLAYER', 'YELLOW_PLAYER']
for p in players:
    idx = content.find(p)
    if idx != -1:
        snippet = content[idx:idx+200]
        trans_match = re.search(r'translation ([\d. -]+)', snippet)
        if trans_match:
            print(f'  {p}: translation = {trans_match.group(1).strip()}')
" 2>/dev/null || true

# Record timestamp
date +%s > /tmp/task_start_timestamp
echo "errors_injected: controllers=soccer_player_broken, positions=overlapping, timestep=128" > /tmp/swarm_experiment_baseline

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/swarm_ready.wbt

# Launch Webots with the broken swarm world
echo "Launching Webots with broken swarm world..."
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
echo "World loaded with 3 swarm configuration errors:"
echo "  1. All soccer player controllers = 'soccer_player_broken'"
echo "  2. All robots at overlapping position (0, 0, 0.1)"
echo "  3. basicTimeStep = 128"
echo "Agent must discover and fix all errors, then save to /home/ga/Desktop/swarm_ready.wbt"
echo "Hint: The correct soccer player controller is 'soccer_player' (in controllers directory)"
