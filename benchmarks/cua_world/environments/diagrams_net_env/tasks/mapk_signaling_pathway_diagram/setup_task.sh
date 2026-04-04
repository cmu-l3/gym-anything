#!/bin/bash
set -e

echo "=== Setting up MAPK Signaling Pathway Diagram Task ==="

# 1. Create directory structure
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the starter diagram (XML format)
# Contains: Title, Extracellular Space, Membrane line, Cytoplasm, Nucleus
cat > /home/ga/Diagrams/mapk_pathway.drawio << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="draw.io" modified="2024-01-01T00:00:00.000Z" agent="draw.io" version="26.0.9" type="device">
  <diagram id="pathway-1" name="MAPK-ERK Signaling Pathway">
    <mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="827" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <mxCell id="2" value="&lt;font style=&quot;font-size: 18px;&quot;&gt;&lt;b&gt;MAPK/ERK Signaling Pathway&lt;/b&gt;&lt;/font&gt;" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;" vertex="1" parent="1">
          <mxGeometry x="380" y="10" width="300" height="40" as="geometry"/>
        </mxCell>
        <mxCell id="3" value="Extracellular Space" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeColor=#666666;dashed=1;verticalAlign=top;fontStyle=1;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="80" y="55" width="1000" height="120" as="geometry"/>
        </mxCell>
        <mxCell id="4" value="" style="endArrow=none;html=1;strokeWidth=4;strokeColor=#B85450;" edge="1" parent="1">
          <mxGeometry relative="1" as="geometry">
            <mxPoint x="80" y="180" as="sourcePoint"/>
            <mxPoint x="1080" y="180" as="targetPoint"/>
          </mxGeometry>
        </mxCell>
        <mxCell id="5" value="Cell Membrane" style="text;html=1;align=right;verticalAlign=middle;resizable=0;points=[];autosize=1;fontStyle=2;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="950" y="160" width="110" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="6" value="Cytoplasm" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;dashed=1;verticalAlign=top;fontStyle=1;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="80" y="190" width="1000" height="370" as="geometry"/>
        </mxCell>
        <mxCell id="7" value="Nucleus" style="ellipse;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;dashed=1;verticalAlign=top;fontStyle=1;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="230" y="580" width="600" height="200" as="geometry"/>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# 3. Create Requirements Document
cat > /home/ga/Desktop/pathway_requirements.txt << 'EOF'
MAPK/ERK SIGNALING PATHWAY DIAGRAM REQUIREMENTS
===============================================

Please complete the diagram "mapk_pathway.drawio" by adding the following components.
Ensure strict adherence to the location and color coding.

1. MOLECULES & LOCATIONS:
   ----------------------
   A. Extracellular Space:
      - Shape: EGF (Label: "EGF")
      - Color: Coral Red (#F08080)
   
   B. Cell Membrane:
      - Shape: EGFR (Receptor) (Label: "EGFR")
      - Color: Teal (#008080)
   
   C. Cytoplasm:
      - Shape: GRB2 (Label: "GRB2") -> Color: Sky Blue
      - Shape: SOS (Label: "SOS")   -> Color: Sky Blue
      - Shape: RAS (Label: "RAS")   -> Color: Amber/Orange (Use a Diamond shape)
      - Shape: RAF (Label: "RAF")   -> Color: Light Green
      - Shape: MEK (Label: "MEK")   -> Color: Light Green
      - Shape: ERK (Label: "ERK")   -> Color: Light Green
   
   D. Nucleus:
      - Shape: ELK1 (Label: "ELK1") -> Color: Purple
      - Shape: MYC (Label: "MYC")   -> Color: Purple

2. CONNECTIONS (Signal Flow):
   --------------------------
   Connect the molecules with directed arrows in this order:
   EGF -> EGFR
   EGFR -> GRB2
   GRB2 -> SOS
   SOS -> RAS
   RAS -> RAF
   RAF -> MEK
   MEK -> ERK
   ERK -> ELK1
   ERK -> MYC

3. ANNOTATIONS:
   ------------
   - Add a small text label "P" next to the arrows connecting RAF->MEK and MEK->ERK to indicate phosphorylation.

4. LEGEND:
   -------
   - Create a small legend box explaining the colors:
     * Red: Ligand
     * Teal: Receptor
     * Blue: Adaptor
     * Green: Kinase
     * Purple: Transcription Factor

5. EXPORT:
   -------
   - Save the diagram (Ctrl+S).
   - Export the diagram as a PNG image.
   - Save to: /home/ga/Diagrams/exports/mapk_pathway.png
   - Ensure "Include a copy of my diagram" is UNCHECKED (optional, but keeps file size small).

===============================================
EOF

# Set permissions
chown -R ga:ga /home/ga/Diagrams
chown ga:ga /home/ga/Desktop/pathway_requirements.txt

# 4. Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io with the file
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/mapk_pathway.drawio > /dev/null 2>&1 &"

# 6. Handle Dialogs (Update & Startup)
echo "Waiting for draw.io..."
sleep 5

# Aggressively dismiss update dialog if it appears
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -i "update"; then
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    fi
done
# Dismiss generic startup dialogs just in case
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 7. Maximize Window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="