#!/bin/bash
set -e

echo "=== Setting up Game AI Behavior Tree Task ==="

# Ensure directories exist
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Diagrams/exports
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 1. Create the Logic Specification File
cat > /home/ga/Desktop/zombie_logic_spec.txt << 'EOF'
NPC: Zombie Guard
Type: Behavior Tree Specification

PRIORITY 1: SELF-PRESERVATION
- Logic: IF Health is Critical, THEN retreat and heal.
- Structure: Sequence
  1. Condition: Health < 20%
  2. Action: Find Cover
  3. Action: Eat Brains (Heal)

PRIORITY 2: COMBAT
- Logic: IF Player is Visible, THEN attack. Choose attack based on distance.
- Structure: Sequence
  1. Condition: Player Visible
  2. Sub-Structure: Selector (Attack Choice)
     - Option A (Melee): Sequence
       1. Condition: Distance < 2 meters
       2. Action: Bite Attack
     - Option B (Ranged): Sequence
       1. Condition: Distance >= 2 meters
       2. Action: Spit Acid

PRIORITY 3: INVESTIGATE
- Logic: IF Noise is Heard, THEN go check it out.
- Structure: Sequence
  1. Condition: Noise Heard
  2. Action: Move to Noise Source
  3. Action: Play Sound "Groan"

PRIORITY 4: IDLE (Patrol)
- Logic: Default behavior if nothing else triggers.
- Structure: Selector (Randomly pick one)
  - Option A: Sequence -> Action: Wander Randomly
  - Option B: Sequence -> Action: Sleep (Stand Still)

ROOT NODE
- The Root should connect to a MAIN SELECTOR which evaluates these 4 branches in order (1 -> 2 -> 3 -> 4).
EOF

# 2. Create the Style Guide
cat > /home/ga/Desktop/behavior_tree_style_guide.txt << 'EOF'
STYLE GUIDE FOR BEHAVIOR TREES

1. CONTROL NODES (Selector, Sequence)
   - Shape: Rectangle (Square corners)
   - Fill Color: Grey / White (#f5f5f5)
   - Label: Must contain "Selector" (?) or "Sequence" (->)

2. CONDITIONS (Checks)
   - Shape: Rhombus (Diamond) OR Hexagon
   - Fill Color: Light Yellow (#fff2cc)
   - Examples: "Health < 20%", "Player Visible"

3. ACTIONS (Leaf Nodes)
   - Shape: Rounded Rectangle
   - Fill Color: Light Blue (#dae8fc)
   - Examples: "Find Cover", "Bite Attack"

4. CONNECTIONS
   - Lines: Solid arrows from Parent to Child
   - Layout: Top-down or Left-to-right hierarchy
EOF

# Set permissions for specs
chown ga:ga /home/ga/Desktop/zombie_logic_spec.txt
chown ga:ga /home/ga/Desktop/behavior_tree_style_guide.txt

# 3. Clean previous task artifacts
rm -f /home/ga/Diagrams/zombie_behavior_tree.drawio
rm -f /home/ga/Diagrams/exports/zombie_behavior_tree.png

# 4. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# 5. Handle Update Dialogs (Aggressive)
sleep 5
echo "Checking for update dialogs..."
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -qiE "update|confirm"; then
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    else
        break
    fi
done

# Double check
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Record start time
date +%s > /tmp/task_start_time.txt

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="