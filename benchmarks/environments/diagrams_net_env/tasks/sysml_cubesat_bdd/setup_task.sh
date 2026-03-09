#!/bin/bash
set -e

echo "=== Setting up SysML CubeSat BDD Task ==="

# Ensure directories exist
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# Clean up previous runs
rm -f /home/ga/Diagrams/aurora3_bdd.drawio
rm -f /home/ga/Diagrams/aurora3_bdd.pdf

# Create the Engineering Specification File
SPEC_FILE="/home/ga/Desktop/aurora3_power_spec.txt"
cat > "$SPEC_FILE" << 'EOF'
From: Chief Engineer <sarah.jenkins@aurora-space.com>
Date: Oct 24, 2024
Subject: Aurora-3 Power Subsystem Architecture for CDR

Hi Team,

We need to finalize the Block Definition Diagram (BDD) for the Aurora-3 Power Subsystem (EPS) before the Critical Design Review on Friday.

Please create a SysML BDD in draw.io. Make sure to use the formal SysML "Block" shapes and "Composition" (solid/filled diamond) connectors.

Here is the breakdown of the **Power Subsystem** (Root Block):

1.  **Solar Generation Assembly**
    - The system uses **4** distinct **Solar Panel** units.
    - Please define a "Solar Panel" block.
    - Value Properties to list inside the block:
        - efficiency = 29.5%
        - area = 0.03 m2
    - Multiplicity: 4

2.  **Energy Storage**
    - The system contains **1** **Battery Module**.
    - Value Properties to list inside the block:
        - technology = Li-Ion
        - capacity = 40 Wh
        - voltage = 14.8 V
    - Multiplicity: 1

3.  **Power Distribution**
    - The system has **1** **EPS Mainboard**.
    - Value Properties to list inside the block:
        - rails = 3.3V, 5V, 12V
        - mass = 0.25 kg
    - Multiplicity: 1

4.  **Harnessing**
    - Include **1** **Wiring Harness** block.
    - Value Property:
        - mass = 0.05 kg
    - Multiplicity: 1

**Relationships:**
All these components are parts of the "Power Subsystem". Use a directed Composition relationship (solid diamond at the Power Subsystem end).

**Note:**
We initially considered a "Deployable Wing" block, but we scrapped that design. Do NOT include deployable wings. Stick to the body-mounted panels described above.

Please export the diagram as a PDF for the slide deck.

Thanks,
Sarah
EOF

chown ga:ga "$SPEC_FILE"
chmod 644 "$SPEC_FILE"

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Dismiss Update Dialog (Aggressive)
echo "Dismissing potential update dialogs..."
sleep 5
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="