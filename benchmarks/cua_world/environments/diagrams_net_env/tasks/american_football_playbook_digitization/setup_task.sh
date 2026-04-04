#!/bin/bash
set -e

echo "=== Setting up American Football Playbook task ==="

# Ensure directories exist
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 1. Create the Play Call Sheet
cat > /home/ga/Desktop/play_call_sheet.txt << 'EOF'
PLAY CALL: SPIDER 2 Y BANANA
FORMATION: GREEN RIGHT STRONG

ALIGNMENT INSTRUCTIONS:
-----------------------
OFFENSE (Blue Circles):
- Line: Standard 5-man surface (LT, LG, C, RG, RT).
- QB: Under Center.
- FB: I-Formation (4 yards deep).
- HB: I-Formation (7 yards deep).
- Y (Tight End): Attached to the RIGHT side of the line.
- Z (Flanker): Split RIGHT, off the line of scrimmage.
- X (Split End): Split LEFT, on the line of scrimmage.

DEFENSE (Red Xs):
- Front: 4-3 Under (4 down linemen).

ASSIGNMENTS / ROUTES:
---------------------
- FB: "Spider" action. Fake block then slide into the RIGHT FLAT. (Curved Arrow)
- Y (Primary): "Banana" route. Run 5 yards, break out, then curve upfield deep. (Curved Arrow)
- Z: "Shallow Cross". Cross the field horizontally at 3-5 yards depth. (Straight Arrow)
- X: "Post". Run 10 yards, break 45 degrees toward the goal post. (Straight Arrow)
- HB: Fake the run, then pass block right.
- QB: Fake handoff to HB, then rollout/bootleg RIGHT. (Dashed Line)
EOF

# 2. Create the Draw.io Template (Football Field)
# This XML defines a green background and a palette of shapes on the side
cat > /home/ga/Diagrams/playbook_template.drawio << 'EOF'
<mxfile host="Electron" modified="2024-03-01T12:00:00.000Z" agent="Mozilla/5.0" version="22.1.0" type="device">
  <diagram id="field_template" name="Playbook">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1100" pageHeight="850" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        
        <!-- Field Background -->
        <mxCell id="field_bg" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#2D7D32;strokeColor=none;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="800" height="600" as="geometry" />
        </mxCell>
        
        <!-- Hash Marks (simplified) -->
        <mxCell id="hash_l" value="" style="endArrow=none;dashed=1;html=1;strokeColor=#FFFFFF;strokeWidth=2;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="300" y="640" as="sourcePoint" />
            <mxPoint x="300" y="40" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <mxCell id="hash_r" value="" style="endArrow=none;dashed=1;html=1;strokeColor=#FFFFFF;strokeWidth=2;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="580" y="640" as="sourcePoint" />
            <mxPoint x="580" y="40" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <mxCell id="los" value="Line of Scrimmage" style="endArrow=none;html=1;strokeColor=#FFFFFF;strokeWidth=4;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="40" y="400" as="sourcePoint" />
            <mxPoint x="840" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>

        <!-- Sidebar Palette Label -->
        <mxCell id="palette_label" value="PLAYER PALETTE (Drag &amp; Copy)" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontStyle=1;fontSize=14;" vertex="1" parent="1">
          <mxGeometry x="860" y="40" width="200" height="30" as="geometry" />
        </mxCell>

        <!-- Offensive Player Template -->
        <mxCell id="off_temp" value="O" style="ellipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor=#DAE8FC;strokeColor=#6C8EBF;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="935" y="100" width="50" height="50" as="geometry" />
        </mxCell>
        <mxCell id="off_label" value="Offense" style="text;html=1;align=center;verticalAlign=middle;" vertex="1" parent="1">
          <mxGeometry x="930" y="150" width="60" height="20" as="geometry" />
        </mxCell>

        <!-- Defensive Player Template -->
        <mxCell id="def_temp" value="X" style="text;html=1;strokeColor=#B85450;fillColor=#F8CECC;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=35;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="935" y="200" width="50" height="50" as="geometry" />
        </mxCell>
        <mxCell id="def_label" value="Defense" style="text;html=1;align=center;verticalAlign=middle;" vertex="1" parent="1">
          <mxGeometry x="930" y="250" width="60" height="20" as="geometry" />
        </mxCell>

      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# Set permissions
chown -R ga:ga /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop
chmod 644 /home/ga/Desktop/play_call_sheet.txt
chmod 644 /home/ga/Diagrams/playbook_template.drawio

# 3. Launch Draw.io
echo "Launching draw.io..."
# Use su to run as ga user
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/playbook_template.drawio > /tmp/drawio.log 2>&1 &"

# 4. Handle Update Dialog (Aggressive Dismissal)
echo "Waiting for application to load..."
sleep 5

dismiss_dialog() {
    # Try multiple keys to dismiss typical "Update Available" or "Open File" dialogs
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    DISPLAY=:1 xdotool key Return
}

# Try to dismiss potential update dialogs for 15 seconds
for i in {1..5}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Attempting to dismiss dialogs..."
        dismiss_dialog
    fi
    sleep 2
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt
echo "Initial state recorded."

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="