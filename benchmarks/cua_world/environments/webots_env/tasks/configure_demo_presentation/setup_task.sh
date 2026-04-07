#!/bin/bash
# Setup script for configure_demo_presentation task
# Loads a standard e-puck world and explicitly injects the "bad" initial state
# (ground-level camera, gray background, empty title).

echo "=== Setting up configure_demo_presentation task ==="

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

# Find the standard e-puck world
DEMO_WORLD="$WEBOTS_HOME/projects/robots/gctronic/e-puck/worlds/e-puck.wbt"
if [ ! -f "$DEMO_WORLD" ]; then
    echo "Searching for e-puck.wbt..."
    DEMO_WORLD=$(find "$WEBOTS_HOME" -name "e-puck.wbt" -type f 2>/dev/null | head -1)
fi

if [ -z "$DEMO_WORLD" ] || [ ! -f "$DEMO_WORLD" ]; then
    echo "ERROR: e-puck.wbt not found in Webots installation"
    exit 1
fi

echo "Found base world: $DEMO_WORLD"

# Copy world and dependencies to writable location
USER_WORLD="/home/ga/webots_projects/demo_scenario.wbt"
mkdir -p /home/ga/webots_projects
cp "$DEMO_WORLD" "$USER_WORLD"
chown -R ga:ga /home/ga/webots_projects

# Python script to inject the "bad" initial state
echo "Injecting initial unconfigured state..."
python3 -c "
import re

with open('$USER_WORLD', 'r') as f:
    content = f.read()

# 1. WorldInfo title: set to empty
world_info_idx = content.find('WorldInfo {')
if world_info_idx != -1:
    end_idx = content.find('}', world_info_idx)
    segment = content[world_info_idx:end_idx]
    if 'title' in segment:
        segment = re.sub(r'title\s+\"[^\"]*\"', 'title \"\"', segment)
    else:
        segment = segment.replace('WorldInfo {', 'WorldInfo {\n  title \"\"')
    content = content[:world_info_idx] + segment + content[end_idx:]

# 2. Viewpoint: set position near ground and FOV to default
vp_idx = content.find('Viewpoint {')
if vp_idx != -1:
    end_idx = content.find('}', vp_idx)
    segment = content[vp_idx:end_idx]
    
    # Replace position
    if 'position' in segment:
        segment = re.sub(r'position\s+[\d.-]+\s+[\d.-]+\s+[\d.-]+', 'position 0 0 0.1', segment)
    else:
        segment = segment.replace('Viewpoint {', 'Viewpoint {\n  position 0 0 0.1')
        
    # Replace fieldOfView
    if 'fieldOfView' in segment:
        segment = re.sub(r'fieldOfView\s+[\d.-]+', 'fieldOfView 0.7854', segment)
    else:
        segment = segment.replace('Viewpoint {', 'Viewpoint {\n  fieldOfView 0.7854')
        
    content = content[:vp_idx] + segment + content[end_idx:]

# 3. Background: set skyColor to flat gray
bg_idx = content.find('Background {')
if bg_idx != -1:
    end_idx = content.find('}', bg_idx)
    segment = content[bg_idx:end_idx]
    
    # Replace skyColor
    if 'skyColor' in segment:
        segment = re.sub(r'skyColor\s+\[?[ \d.-]+\]?', 'skyColor 0.7 0.7 0.7', segment)
    else:
        segment = segment.replace('Background {', 'Background {\n  skyColor 0.7 0.7 0.7')
        
    content = content[:bg_idx] + segment + content[end_idx:]

with open('$USER_WORLD', 'w') as f:
    f.write(content)
"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/demo_configured.wbt

# Launch Webots
echo "Launching Webots with unconfigured demo world..."
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
echo "World loaded: $USER_WORLD"
echo "Agent should:"
echo "  1. Set WorldInfo title to 'Robot Navigation Demo - TechExpo 2024'"
echo "  2. Set Viewpoint position to 0 0 3.0 and fieldOfView to 1.2"
echo "  3. Set Background skyColor to 0.05 0.05 0.2"
echo "  4. Save to /home/ga/Desktop/demo_configured.wbt"