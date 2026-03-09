#!/bin/bash
# setup_task.sh for northwind_data_vault_architecture
set -u

echo "=== Setting up Northwind Data Vault task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the Requirements File
cat > /home/ga/Desktop/dv_requirements.txt << 'EOF'
Data Vault 2.0 Modeling Requirements
====================================
Source System: Northwind ERP (Legacy)
Subject Area: Sales

SOURCE SCHEMA
-------------
1. Customers (CustomerID (PK), CompanyName, ContactName, Address, City, Country)
2. Orders (OrderID (PK), CustomerID (FK), OrderDate, ShipCity, ShipCountry)
3. Products (ProductID (PK), ProductName, UnitPrice, Discontinued)
4. OrderDetails (OrderID (FK), ProductID (FK), UnitPrice, Quantity)

MODELING STANDARDS (Data Vault 2.0)
-----------------------------------
1. ENTITIES
   - HUBS: Represent core business keys. 
     Color: Blue (#dae8fc). 
     Naming: Hub_<EntityName>
     Standard Cols: <PK>, <PK>_HashKey, LoadDate, RecordSource

   - LINKS: Represent transactions/relationships.
     Color: Red/Pink (#f8cecc).
     Naming: Link_<Entity1>_<Entity2>
     Standard Cols: <Link>_HashKey, LoadDate, RecordSource

   - SATELLITES: Represent descriptive context/attributes.
     Color: Yellow (#fff2cc).
     Naming: Sat_<EntityName>
     Standard Cols: <Parent>_HashKey, LoadDate, RecordSource, HashDiff + Attributes

2. REQUIRED MODEL
   - Create Hubs for: Customer, Order, Product
   - Create Links for: Order-to-Customer, Order-to-Product (Line Item)
   - Create Satellites for each Hub containing the non-key attributes

3. DELIVERABLES
   - Draw.io XML file: ~/Desktop/northwind_dv.drawio
   - PNG Export: ~/Desktop/northwind_dv.png
EOF

chown ga:ga /home/ga/Desktop/dv_requirements.txt
chmod 644 /home/ga/Desktop/dv_requirements.txt

# 2. Ensure draw.io is ready
# Kill any existing instances
pkill -f drawio 2>/dev/null || true

# Launch draw.io
echo "Launching draw.io..."
# We use a wrapper or direct call depending on install, mirroring standard env setup
DRAWIO_BIN=$(which drawio || echo "/opt/drawio/drawio")
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss startup dialog (creates blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="