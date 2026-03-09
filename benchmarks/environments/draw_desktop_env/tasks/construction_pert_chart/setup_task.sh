#!/bin/bash
# setup_task.sh for construction_pert_chart
set -e

echo "=== Setting up construction_pert_chart task ==="

# 1. Create the schedule file
cat > /home/ga/Desktop/renovation_schedule.txt << 'EOF'
PROJECT: COMMUNITY CENTER RENOVATION
====================================
INSTRUCTIONS:
1. Create a PERT Chart (Network Diagram) for the tasks below.
2. Nodes should show Task Name and Duration.
3. Draw arrows from Predecessors to Successors.
4. HIGHLIGHT THE CRITICAL PATH: Make the arrows connecting the Critical Path tasks RED and THICK.

TASK LIST:
ID | Task Name           | Duration | Predecessors (Must finish before this starts)
---|---------------------|----------|----------------------------------------------
1  | Demolition          | 10 days  | (None - Start)
2  | Structural Repair   | 15 days  | 1
3  | Rough Plumbing      | 5 days   | 1
4  | Rough Electrical    | 7 days   | 1
5  | HVAC Install        | 8 days   | 2
6  | Drywall             | 10 days  | 3, 4, 5
7  | Painting            | 5 days   | 6
8  | Flooring            | 7 days   | 7
9  | Fixtures            | 5 days   | 7
10 | Final Cleanup       | 3 days   | 8, 9

CRITICAL PATH ANALYSIS:
The Critical Path is the longest sequence of dependent tasks.
Critical Sequence: 1 -> 2 -> 5 -> 6 -> 7 -> 8 -> 10
(Demolition -> Structural Repair -> HVAC Install -> Drywall -> Painting -> Flooring -> Final Cleanup)

Total Duration: 58 Days

NOTE: Tasks 3 (Plumbing), 4 (Electrical), and 9 (Fixtures) are NOT on the critical path. 
Do not highlight lines connected to them.
EOF

chown ga:ga /home/ga/Desktop/renovation_schedule.txt
chmod 644 /home/ga/Desktop/renovation_schedule.txt

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous runs
rm -f /home/ga/Desktop/pert_chart.drawio
rm -f /home/ga/Desktop/pert_chart.png

# 4. Launch draw.io
# We launch it and dismiss the startup dialog to ensure a blank canvas is ready
echo "Launching draw.io..."
DRAWIO_BIN="drawio"
if [ -f "/opt/drawio/drawio" ]; then DRAWIO_BIN="/opt/drawio/drawio"; fi

su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Esc) to get blank canvas
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="