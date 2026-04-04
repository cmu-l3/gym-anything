#!/bin/bash
set -e

echo "=== Setting up Warehouse Layout Optimization Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Generate Inventory Data (CSV)
# Top 4: Phone Acc, Cons Elec, Vitamins, Pet Food
# Bottom 4: Kayak, Winter Tires, Lawn Mowers, Pool Tables
cat > /home/ga/Desktop/inventory_velocity.csv << 'CSVEOF'
Category,Daily_Pick_Count,Avg_Weight_Lbs
Phone Accessories,1250,0.5
Consumer Electronics,1100,2.1
Vitamins & Supplements,980,0.8
Pet Food,850,15.0
Kitchenware,420,3.5
Bedding & Linens,350,4.2
Office Supplies,310,1.2
Auto Parts,280,5.5
Garden Tools,250,6.0
Camping Gear,180,8.5
Furniture (Flat Pack),45,45.0
Kayak Accessories,12,3.2
Winter Tires,8,22.0
Lawn Mowers,5,65.0
Pool Tables,2,150.0
CSVEOF

# 3. Generate Rules Text
cat > /home/ga/Desktop/slotting_rules.txt << 'RULESEOF'
WAREHOUSE SLOTTING OPTIMIZATION RULES

1. IDENTIFY VELOCITY
   - Review 'inventory_velocity.csv'.
   - The Top 4 categories by pick count are "Fast Movers".
   - The Bottom 4 categories by pick count are "Slow Movers".

2. DEFINE ZONES
   - ZONE A (Gold Zone): The area immediately adjacent to the Packing/Shipping stations (East side).
   - ZONE B (Silver Zone): The middle aisles.
   - ZONE C (Bronze Zone): The far rear of the warehouse (West side).

3. EXECUTE MOVES
   - Move all "Fast Mover" racks into ZONE A.
   - Move all "Slow Mover" racks into ZONE C.
   - Maintain clear aisles.
   - Do not overlap racks with the Office or Walls.

4. VISUALIZE FLOW
   - Add a label or visual marker for ZONE A.
   - Draw a directional arrow line showing the "Pick Path" from Office -> Aisles -> Packing.

5. EXPORT
   - Save as PDF to ~/Diagrams/exports/optimized_layout.pdf
RULESEOF

# 4. Generate Initial Draw.io XML
# We use Python to generate a clean, uncompressed XML file.
# The layout places fast movers FAR (West) and slow movers NEAR (East) to force the agent to fix it.
cat > /tmp/gen_diagram.py << 'PYEOF'
import xml.etree.ElementTree as ET

def create_mxcell(id, value, style, parent, x=0, y=0, w=0, h=0, vertex="1", edge="0"):
    attribs = {"id": str(id), "parent": str(parent)}
    if value: attribs["value"] = value
    if style: attribs["style"] = style
    if vertex == "1": attribs["vertex"] = "1"
    if edge == "1": attribs["edge"] = "1"
    
    cell = ET.Element("mxCell", attribs)
    if vertex == "1":
        ET.SubElement(cell, "mxGeometry", {"x": str(x), "y": str(y), "width": str(w), "height": str(h), "as": "geometry"})
    return cell

root_xml = ET.Element("mxfile", {"host": "Electron", "type": "device"})
diagram = ET.SubElement(root_xml, "diagram", {"name": "Warehouse Floor Plan", "id": "uuid-1234"})
mx_model = ET.SubElement(diagram, "mxGraphModel", {"dx": "1422", "dy": "798", "grid": "1", "gridSize": "10", "guides": "1", "tooltips": "1", "connect": "1", "arrows": "1", "fold": "1", "page": "1", "pageScale": "1", "pageWidth": "850", "pageHeight": "1100", "background": "#ffffff"})
root = ET.SubElement(mx_model, "root")

ET.SubElement(root, "mxCell", {"id": "0"})
ET.SubElement(root, "mxCell", {"id": "1", "parent": "0"})

# FIXED INFRASTRUCTURE
# Walls (800x600)
root.append(create_mxcell(2, "Warehouse Perimeter", "rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeWidth=3;", 1, 40, 40, 800, 600))
# Shipping Dock (East side, x=740)
root.append(create_mxcell(3, "SHIPPING DOCK\n(DO NOT BLOCK)", "rounded=0;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontStyle=1;locked=1;", 1, 740, 200, 100, 300))
# Packing Area (East side, x=600)
root.append(create_mxcell(4, "Packing Area", "rounded=0;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontStyle=1;locked=1;", 1, 600, 200, 100, 300))
# Office (South West, x=40)
root.append(create_mxcell(5, "Office", "rounded=0;whiteSpace=wrap;html=1;fillColor=#f5f5f5;fontStyle=1;locked=1;", 1, 40, 500, 150, 140))

# MOVABLE RACKS (Inefficient Layout)
# Fast Movers (Should be East, currently West x=100)
fast = ["Phone Accessories", "Consumer Electronics", "Vitamins", "Pet Food"]
y_pos = 100
for name in fast:
    root.append(create_mxcell(10 + fast.index(name), f"Rack - {name}", "shape=cube;whiteSpace=wrap;html=1;fillColor=#fff2cc;", 1, 100, y_pos, 40, 100))
    y_pos += 120

# Slow Movers (Should be West, currently East x=500)
slow = ["Pool Tables", "Lawn Mowers", "Winter Tires", "Kayak Accessories"]
y_pos = 100
for name in slow:
    root.append(create_mxcell(20 + slow.index(name), f"Rack - {name}", "shape=cube;whiteSpace=wrap;html=1;fillColor=#e1d5e7;", 1, 500, y_pos, 40, 100))
    y_pos += 120

# Medium Movers (Middle x=300)
medium = ["Kitchenware", "Bedding", "Office Supplies", "Auto Parts"]
y_pos = 100
for name in medium:
    root.append(create_mxcell(30 + medium.index(name), f"Rack - {name}", "shape=cube;whiteSpace=wrap;html=1;fillColor=#f8cecc;", 1, 300, y_pos, 40, 100))
    y_pos += 120

tree = ET.ElementTree(root_xml)
tree.write("/home/ga/Diagrams/warehouse_current.drawio", encoding="UTF-8", xml_declaration=True)
PYEOF

python3 /tmp/gen_diagram.py

# 5. Set Permissions
chown -R ga:ga /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop

# 6. Record Initial State
date +%s > /tmp/task_start_time
ls -l /home/ga/Diagrams/warehouse_current.drawio > /tmp/initial_file_state

# 7. Launch draw.io (optional, helps agent start faster)
# su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/warehouse_current.drawio &"
# sleep 5
# DISMISS UPDATE DIALOG logic would go here if we auto-launched

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="