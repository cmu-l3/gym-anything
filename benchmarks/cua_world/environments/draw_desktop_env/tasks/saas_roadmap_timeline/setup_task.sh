#!/bin/bash
set -u

echo "=== Setting up saas_roadmap_timeline task ==="

# 1. Create the data file
cat > /home/ga/Desktop/roadmap_data.txt << 'EOF'
2025 PRODUCT ROADMAP INITIATIVES

INSTRUCTIONS:
- Map these to the timeline (Q1-Q4 2025).
- Use Swimlanes for Teams.
- Color code by Status: Completed=Green, Planned=Blue, Risky=Red.

INITIATIVES LIST:
1. SSO Integration
   - Team: Backend Team
   - Timing: Q1 2025
   - Status: Completed

2. Dashboard Redesign
   - Team: Frontend Team
   - Timing: Q1 2025 (extending into Q2)
   - Status: Planned

3. iOS App Beta
   - Team: Mobile Team
   - Timing: Q2 2025
   - Status: Risky

4. API Migration
   - Team: Backend Team
   - Timing: Q2 2025
   - Status: Planned

5. Product Launch v2.0 (Milestone)
   - Timing: End of Q2 2025
   - Shape: Diamond

6. Android Launch
   - Team: Mobile Team
   - Timing: Q3 2025
   - Status: Planned

7. Dark Mode
   - Team: Frontend Team
   - Timing: Q4 2025
   - Status: Planned
EOF
chown ga:ga /home/ga/Desktop/roadmap_data.txt
chmod 644 /home/ga/Desktop/roadmap_data.txt

# 2. Cleanup previous runs
rm -f /home/ga/Desktop/roadmap.drawio /home/ga/Desktop/roadmap.png
date +%s > /tmp/task_start_time.txt

# 3. Launch draw.io
# We launch it without a file so the "Create New / Open Existing" dialog appears.
# The agent must handle creating a new diagram.
echo "Launching draw.io..."
DRAWIO_BIN="drawio"
if [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio"; fi

su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# 4. Wait for window
echo "Waiting for draw.io..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        break
    fi
    sleep 1
done

# 5. Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Setup screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="