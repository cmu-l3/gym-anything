#!/bin/bash
set -e
echo "=== Setting up Argument Map Task ==="

# 1. Prepare Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure directories exist
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 3. Create the Debate Structure Text File
cat > /home/ga/Desktop/debate_structure.txt << 'EOF'
# AI REGULATION DEBATE - ARGUMENT MAP STRUCTURE

**INSTRUCTIONS:**
Create an Argument Map in draw.io based on the structure below.
- Use Rectangle shapes for all nodes.
- Use Line/Arrow shapes for connections.
- Follow the visual style guide strictly.

**VISUAL STYLE GUIDE:**
- **SUPPORTING** Links: Color = Green (#00CC00), Style = Solid Line
- **OPPOSING** Links: Color = Red (#FF0000), Style = Dashed Line
- **LAYOUT**: Place Supporting arguments on the LEFT, Opposing on the RIGHT.

---

## CENTRAL CLAIM
**Text**: "Immediate 6-Month Pause on Giant AI Experiments"
**Position**: Center of the diagram

---

## SUPPORTING ARGUMENTS (Place on LEFT, Link to Central Claim)

1. **Argument A**
   - **Text**: "Risk of Flooding Information Channels with Propaganda"
   - **Type**: Support (Green/Solid arrow to Central Claim)

2. **Argument B**
   - **Text**: "Loss of Human Control over Civilization"
   - **Type**: Support (Green/Solid arrow to Central Claim)

3. **Argument C**
   - **Text**: "Lack of Regulatory Frameworks"
   - **Type**: Support (Green/Solid arrow to Central Claim)

---

## OPPOSING ARGUMENTS (Place on RIGHT, Link to Central Claim)

4. **Argument D**
   - **Text**: "Geopolitical Disadvantage vs Adversaries"
   - **Type**: Oppose (Red/Dashed arrow to Central Claim)

5. **Argument E**
   - **Text**: "Stifles Scientific Innovation & Medical Breakthroughs"
   - **Type**: Oppose (Red/Dashed arrow to Central Claim)

6. **Argument F**
   - **Text**: "Implementation is Technically Infeasible"
   - **Type**: Oppose (Red/Dashed arrow to Central Claim)

---

## REBUTTALS (Link to the specific argument they attack)

7. **Rebuttal to Argument D** (Connect this TO Argument D)
   - **Text**: "International Treaties Can Mitigate Geopolitical Risks"
   - **Type**: Oppose (Red/Dashed arrow to Argument D)

8. **Rebuttal to Argument C** (Connect this TO Argument C)
   - **Text**: "Existing AI Safety Guidelines are Sufficient"
   - **Type**: Oppose (Red/Dashed arrow to Argument C)
EOF
chown ga:ga /home/ga/Desktop/debate_structure.txt

# 4. Create a Blank Starter Diagram
# This ensures the agent works on the correct file path
cat > /home/ga/Diagrams/ai_argument_map.drawio << 'EOF'
<mxfile host="Electron" modified="2024-01-01T00:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/26.0.9 Chrome/128.0.6613.186 Electron/32.2.5 Safari/537.36" version="26.0.9" etag="START">
  <diagram id="START" name="Page-1">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF
chown ga:ga /home/ga/Diagrams/ai_argument_map.drawio

# 5. Clean up previous exports
rm -f /home/ga/Diagrams/exports/ai_argument_map.pdf

# 6. Launch draw.io
echo "Launching draw.io..."
# We use sudo -u ga to run as the user
# We use the full path to the AppImage
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/ai_argument_map.drawio > /dev/null 2>&1 &"

# 7. Wait for window and handle update dialogs
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io detected"
        break
    fi
    sleep 1
done
sleep 5

# Dismiss update dialog if it appears (common in AppImage)
# Try Escape, then Tab-Tab-Enter
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="