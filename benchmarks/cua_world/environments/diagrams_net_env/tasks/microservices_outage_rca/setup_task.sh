#!/bin/bash
echo "=== Setting up microservices_outage_rca task ==="

# ---- Create directories ----
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Diagrams /home/ga/Desktop

# ---- Copy data files ----
cp /workspace/tasks/microservices_outage_rca/data/shopstream_architecture.drawio /home/ga/Diagrams/shopstream_architecture.drawio
cp /workspace/tasks/microservices_outage_rca/data/incident_timeline.csv /home/ga/Desktop/incident_timeline.csv
cp /workspace/tasks/microservices_outage_rca/data/service_dependencies.csv /home/ga/Desktop/service_dependencies.csv
chown ga:ga /home/ga/Diagrams/shopstream_architecture.drawio
chown ga:ga /home/ga/Desktop/incident_timeline.csv
chown ga:ga /home/ga/Desktop/service_dependencies.csv

# ---- Delete stale outputs BEFORE recording timestamp ----
rm -f /home/ga/Diagrams/shopstream_rca.pdf 2>/dev/null || true

# ---- Record task start timestamp ----
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# ---- Record baseline shape/edge/page counts from starter diagram ----
DRAWIO_FILE="/home/ga/Diagrams/shopstream_architecture.drawio"
if [ -f "$DRAWIO_FILE" ]; then
    SHAPE_COUNT=$(grep -o 'vertex="1"' "$DRAWIO_FILE" | wc -l)
    EDGE_COUNT=$(grep -o 'edge="1"' "$DRAWIO_FILE" | wc -l)
    PAGE_COUNT=$(grep -o '<diagram ' "$DRAWIO_FILE" | wc -l)
    echo "$SHAPE_COUNT" > /tmp/initial_shape_count
    echo "$EDGE_COUNT" > /tmp/initial_edge_count
    echo "$PAGE_COUNT" > /tmp/initial_page_count
    echo "Initial counts: shapes=$SHAPE_COUNT edges=$EDGE_COUNT pages=$PAGE_COUNT"
else
    echo "0" > /tmp/initial_shape_count
    echo "0" > /tmp/initial_edge_count
    echo "1" > /tmp/initial_page_count
fi

# ---- Kill any existing draw.io instances ----
pkill -f drawio 2>/dev/null || true
pkill -f "draw.io" 2>/dev/null || true
sleep 2

# ---- Launch draw.io with the architecture diagram ----
echo "Launching draw.io with architecture diagram..."
# Use xdg-open which correctly associates .drawio files with draw.io desktop app.
# Direct binary invocation with file arg may show a file-open dialog instead of loading the file.
su - ga -c "DISPLAY=:1 xdg-open /home/ga/Diagrams/shopstream_architecture.drawio" > /tmp/drawio.log 2>&1 &
DRAWIO_PID=$!

# ---- Wait for draw.io window to appear ----
echo "Waiting for draw.io window..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io\|drawio\|shopstream"; then
        echo "draw.io window detected after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: draw.io window not detected within timeout"
fi

sleep 3

# ---- Dismiss update dialog aggressively ----
echo "Dismissing any update dialogs..."
for i in $(seq 1 20); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
    sleep 0.3
    # Click "Close" or "Not Now" region if visible
    DISPLAY=:1 xdotool mousemove 960 580 click 1 2>/dev/null || true
    sleep 0.3

    # Check if the main draw.io canvas is showing (no dialog)
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "shopstream_architecture"; then
        echo "File loaded in draw.io at iteration $i"
        break
    fi
done

sleep 2

# ---- Maximize the draw.io window ----
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# ---- Take initial screenshot ----
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== microservices_outage_rca task setup complete ==="
