#!/bin/bash
# Setup script for us_legislation_swimlane
# Do NOT use set -e, as some window checks may fail harmlessly

echo "=== Setting up US Legislation Swimlane Task ==="

# 1. Create Reference Document
cat > /home/ga/Desktop/legislation_reference.txt << 'EOF'
HOW A BILL BECOMES A LAW (FEDERAL LEGISLATIVE PROCESS)

1. INTRODUCTION
   - A bill can be introduced in either the House of Representatives or the Senate.
   - Example: Bill is drafted and introduced in the House.

2. COMMITTEE ACTION (House & Senate)
   - The bill is referred to the appropriate standing committee.
   - The committee holds hearings and "mark-up" sessions to amend the bill.
   - If the committee votes to report the bill, it goes to the floor.

3. FLOOR ACTION (House)
   - The Rules Committee schedules the debate.
   - The House debates the bill.
   - The House votes.
   - DECISION: If it passes (Simple Majority), it moves to the Senate. If it fails, the bill dies.

4. FLOOR ACTION (Senate)
   - The Senate debates the bill (possibility of filibuster, requiring cloture vote).
   - The Senate votes.
   - DECISION: If it passes, check if versions match.

5. RECONCILIATION
   - DECISION: Is the Senate version identical to the House version?
   - If YES: Goes to President.
   - If NO: A Conference Committee (members of both chambers) meets to resolve differences.
   - The Conference Committee issues a report.
   - Both chambers must vote to approve the Conference Report.

6. PRESIDENTIAL ACTION
   - The bill is sent to the President.
   - DECISION: The President has 3 choices:
     A. Sign the bill -> Bill becomes Law.
     B. Veto the bill -> Bill returns to Congress.
     C. Do nothing -> If Congress is in session (10 days), it becomes law. If adjourned, "Pocket Veto" (dies).

7. VETO OVERRIDE (Sub-process)
   - If Vetoed:
   - House votes to override (Requires 2/3 majority).
   - DECISION: If House passes -> Senate votes.
   - Senate votes to override (Requires 2/3 majority).
   - DECISION: If Senate passes -> Bill becomes Law (without signature).
EOF

chown ga:ga /home/ga/Desktop/legislation_reference.txt
chmod 644 /home/ga/Desktop/legislation_reference.txt

# 2. Record Task Start Time (Anti-Gaming)
date +%s > /tmp/task_start_time.txt

# 3. Launch draw.io
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# 4. Wait for Window and Configure
echo "Waiting for window..."
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

# Dismiss "Create New / Open Existing" dialog (Esc -> Blank Diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# 5. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="