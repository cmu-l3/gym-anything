#!/bin/bash
set -e
echo "=== Setting up Product Catalog Bulk Import Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create the Vendor CSV file on Desktop with realistic data (15 items)
cat > /home/ga/Desktop/vendor_catalog_update.csv << 'EOF'
Item Name,SKU,Category,RRP,Wholesale Cost,Weight (kg)
Premium Gel Pen (Black),PEN-GEL-BLK,Writing Instruments,2.50,0.85,0.02
Premium Gel Pen (Blue),PEN-GEL-BLU,Writing Instruments,2.50,0.85,0.02
Premium Gel Pen (Red),PEN-GEL-RED,Writing Instruments,2.50,0.85,0.02
Mechanical Pencil 0.5mm,PCL-MECH-05,Writing Instruments,4.25,1.50,0.03
HB Lead Refills (Pack of 12),REF-LEAD-HB,Writing Instruments,1.20,0.40,0.01
A4 Copy Paper (500 Sheets),PAP-A4-500,Office Paper,6.99,3.50,2.50
A3 Art Paper (100 Sheets),PAP-A3-100,Office Paper,12.50,6.00,1.80
Sticky Notes 3x3 (Yellow),NOT-STK-YEL,Office Paper,1.99,0.50,0.10
Spiral Notebook (Ruled),NB-SPI-RUL,Office Paper,3.50,1.10,0.40
Desktop Tape Dispenser,DSK-TAPE-DISP,Desk Accessories,8.99,3.20,0.60
Stapler (Standard),DSK-STAP-STD,Desk Accessories,7.50,2.80,0.35
Staples 26/6 (Box of 5000),REF-STAP-266,Desk Accessories,2.99,0.90,0.15
Mesh Desk Organizer,DSK-ORG-MESH,Desk Accessories,14.99,6.50,0.80
Whiteboard Marker Set (4 Colors),MRK-WHT-SET,Writing Instruments,5.99,2.20,0.12
Correction Tape 5mm,COR-TAPE-5MM,Writing Instruments,2.25,0.75,0.03
EOF

# Set permissions so agent can access it
chown ga:ga /home/ga/Desktop/vendor_catalog_update.csv
chmod 644 /home/ga/Desktop/vendor_catalog_update.csv

echo "Created CSV file at /home/ga/Desktop/vendor_catalog_update.csv"

# 2. Record Task Start Time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure Odoo is running
echo "Checking Odoo status..."
if ! pgrep -f "odoo-bin" > /dev/null && ! pgrep -f "python3 /usr/bin/odoo" > /dev/null; then
    # In this env, Odoo runs in docker, check container
    if ! docker ps | grep -q odoo-web; then
        echo "Starting Odoo containers..."
        cd /home/ga/odoo && docker-compose up -d
        sleep 10
    fi
fi

# 4. Ensure Firefox is open and logged in
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|odoo"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Focus and maximize
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# 5. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="