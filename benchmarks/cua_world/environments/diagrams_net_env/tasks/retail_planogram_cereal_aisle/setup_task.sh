#!/bin/bash
set -e

echo "=== Setting up Retail Planogram Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 2. Generate Product List CSV
cat > /home/ga/Desktop/product_list.csv << 'CSVEOF'
SKU,Product Name,Category,Width(in),Height(in),Margin,Min Facings
101,FiberCrunch,Adult,8,12,High ($2.50),2
102,ChocoBlast,Kids,7,10,Medium ($1.20),3
103,SugarDust,Kids,7,10,Low ($0.80),3
104,HeartyOats,Adult,6,11,High ($2.10),2
105,BudgetBag,Value,10,14,Low ($0.50),1
CSVEOF

# 3. Generate Merchandising Strategy
cat > /home/ga/Desktop/merchandising_strategy.txt << 'TXTEOF'
MERCHANDISING STRATEGY - CEREAL AISLE
=====================================

1. FIXTURE SPECIFICATIONS
   - Width: 48 inches
   - Height: 72 inches
   - Scale for Diagram: 1 inch = 10 pixels

2. ZONING RULES
   - TOP SHELF (Above 60"): Value & Bulk items.
   - EYE LEVEL (45" - 60" from bottom): High Margin "Adult" cereals. This is the prime real estate.
   - MIDDLE SHELVES (20" - 45"): Core movers & crossovers.
   - BOTTOM SHELF (0" - 20"): "Kids" cereals. (Placed at child's eye level).

3. EXECUTION INSTRUCTIONS
   - Create a box for each "Facing" (e.g. Min Facings: 2 means draw 2 boxes side-by-side).
   - Label every box clearly.
   - Attach a "SALE" star shape to the lowest margin product (BudgetBag or SugarDust).
   - Ensure products do not float in the air; place them on shelf lines.
TXTEOF

# 4. Create Planogram Template (Diagrams.net XML)
# This creates a locked background with 4 shelves
# Total Height 72" = 720px. 
# Shelves at: 0 (Top), 180, 360, 540, 720 (Bottom)
cat > /home/ga/Diagrams/planogram_template.drawio << 'XMELOF'
<mxfile host="Electron" modified="2023-01-01T00:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/20.3.0 Chrome/104.0.5112.114 Electron/20.1.3 Safari/537.36" version="20.3.0" type="device">
  <diagram id="0" name="Page-1">
    <mxGraphModel dx="1422" dy="808" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- Fixture Background (Locked) -->
        <mxCell id="fixture_bg" value="48-inch Fixture (Scale: 1in=10px)" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeColor=#666666;verticalAlign=top;align=center;fontStyle=1;locked=1;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="480" height="720" as="geometry" />
        </mxCell>
        <!-- Shelf 4 (Top) -->
        <mxCell id="shelf_4" value="Top Shelf" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#333333;strokeColor=none;locked=1;" vertex="1" parent="1">
          <mxGeometry x="40" y="220" width="480" height="10" as="geometry" />
        </mxCell>
        <!-- Shelf 3 (Eye Level) -->
        <mxCell id="shelf_3" value="Eye Level Shelf" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#333333;strokeColor=none;locked=1;" vertex="1" parent="1">
          <mxGeometry x="40" y="380" width="480" height="10" as="geometry" />
        </mxCell>
        <!-- Shelf 2 -->
        <mxCell id="shelf_2" value="Mid Shelf" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#333333;strokeColor=none;locked=1;" vertex="1" parent="1">
          <mxGeometry x="40" y="540" width="480" height="10" as="geometry" />
        </mxCell>
        <!-- Base -->
        <mxCell id="base" value="Base Deck" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#333333;strokeColor=none;locked=1;" vertex="1" parent="1">
          <mxGeometry x="40" y="710" width="480" height="50" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XMELOF

# 5. Set ownership
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 6. Record timestamp and launch
date +%s > /tmp/task_start_time.txt

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/planogram_template.drawio &"

# Wait and maximize
sleep 10
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss Update Dialog (Aggressive)
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -i "update"; then
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    fi
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="