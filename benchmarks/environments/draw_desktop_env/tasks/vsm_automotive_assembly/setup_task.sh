#!/bin/bash
# setup_task.sh for vsm_automotive_assembly

echo "=== Setting up VSM Automotive Assembly Task ==="

# 1. Define paths
DATA_FILE="/home/ga/Desktop/acme_stamping_data.txt"
DRAWIO_BIN="drawio"

# 2. Create the Data File (Real-world VSM data)
cat > "$DATA_FILE" << 'EOF'
ACME STAMPING - CURRENT STATE DATA
==================================

CUSTOMER: State Street Assembly
- Demand: 18,400 pieces/month
- Daily Demand: 920 pieces/day (based on 20 working days)
- Containers: Returnable trays of 20 pieces
- Shifts: 1 shift of 8 hours
- Available Time: 27,600 seconds per shift
- Breaks: 2 x 10 min, Lunch: 30 min (already deducted)

SUPPLIER: Michigan Steel Co.
- Delivery: Weekly (every Tuesday)
- Material: 500-foot coils

PROCESS STEPS (Left to Right):

1. STAMPING (Press 200T)
   - Cycle Time (C/T): 1 second
   - Changeover (C/O): 1 hour
   - Uptime: 85%
   - Batch Size: 7,200 pieces
   - Operators: 1

   INVENTORY (Stamping -> Welding I):
   - 4,600 pieces (approx 4.5 days)

2. WELDING I (Spot Weld)
   - Cycle Time (C/T): 38 seconds
   - Changeover (C/O): 10 minutes
   - Uptime: 100%
   - Operators: 2

   INVENTORY (Welding I -> Welding II):
   - 1,100 pieces (approx 1.1 days)

3. WELDING II (Spot Weld)
   - Cycle Time (C/T): 46 seconds
   - Changeover (C/O): 10 minutes
   - Uptime: 80%
   - Operators: 2

   INVENTORY (Welding II -> Assembly I):
   - 1,600 pieces (approx 1.6 days)

4. ASSEMBLY I
   - Cycle Time (C/T): 62 seconds
   - Changeover (C/O): 0
   - Uptime: 100%
   - Operators: 1

   INVENTORY (Assembly I -> Assembly II):
   - 1,200 pieces (approx 1.2 days)

5. ASSEMBLY II
   - Cycle Time (C/T): 40 seconds
   - Changeover (C/O): 0
   - Uptime: 100%
   - Operators: 1

   INVENTORY (Finished Goods -> Shipping):
   - 2,700 pieces (approx 2.7 days)

RAW MATERIAL INVENTORY:
- Coils: 5 days of supply

LOGISTICS:
- Shipping Schedule: Daily
- Supplier Schedule: Weekly

CALCULATIONS REQUIRED:
- Total Processing Time (Sum of Cycle Times)
- Total Production Lead Time (Sum of Inventory Days + Raw Material Days)
EOF

chown ga:ga "$DATA_FILE"
chmod 644 "$DATA_FILE"
echo "Created data file at $DATA_FILE"

# 3. Clean previous run artifacts
rm -f /home/ga/Desktop/acme_vsm.drawio 2>/dev/null
rm -f /home/ga/Desktop/acme_vsm.png 2>/dev/null

# 4. Record anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io
# We launch it with disable-update to prevent popups
echo "Launching draw.io..."
if command -v drawio &>/dev/null; then
    su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true drawio --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"
elif [ -f /opt/drawio/drawio ]; then
    su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true /opt/drawio/drawio --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"
else
    echo "ERROR: draw.io binary not found"
    exit 1
fi

# 6. Wait for window and handle startup dialog
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss "Create New/Open" dialog with Escape (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="