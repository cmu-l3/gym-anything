#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up azure_iot_telemetry_pipeline task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/smart_city_iot.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/smart_city_iot.png 2>/dev/null || true

# Create Requirements Document
cat > /home/ga/Desktop/iot_requirements.txt << 'EOF'
Smart City IoT Telemetry Pipeline
=================================
Project: Urban Temperature Monitoring
Architect: Solutions Architecture Team

Overview:
We need a "Hot/Cold Path" architecture diagram for our new sensor fleet.
Please create a diagram in draw.io using official Azure icons.

Data Flow Specification:
1. Ingestion:
   - Source: "IoT Devices" (Sensors)
   - Target: "Azure IoT Hub"

2. Processing:
   - Source: "Azure IoT Hub"
   - Processor: "Azure Stream Analytics" job

3. Storage & Analytics (Bifurcation):
   - The Stream Analytics job splits data into two paths:
     a) COLD PATH: Raw data is archived in "Azure Data Lake Storage Gen2".
     b) HOT PATH: Aggregated data is sent to "Azure Cosmos DB".

4. Visualization:
   - Dashboard: "Power BI" connects to the Cosmos DB to visualize real-time alerts.

Deliverables:
- Source file: ~/Desktop/smart_city_iot.drawio
- Export image: ~/Desktop/smart_city_iot.png
EOF

chown ga:ga /home/ga/Desktop/iot_requirements.txt
chmod 644 /home/ga/Desktop/iot_requirements.txt

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_iot.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Press Escape to create blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify draw.io is running
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
else
    echo "Warning: draw.io may not have started properly"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/iot_task_start.png 2>/dev/null || true

echo "=== Setup complete ==="