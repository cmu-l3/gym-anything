#!/bin/bash
# Setup script for BPMN Incident Management task
# Do NOT use set -e, as some GUI commands might return non-zero harmlessly

echo "=== Setting up BPMN Incident Management Task ==="

# 1. Define paths and clean up
USER_DESKTOP="/home/ga/Desktop"
SPEC_FILE="$USER_DESKTOP/incident_process_spec.txt"
OUTPUT_FILE="$USER_DESKTOP/incident_management.drawio"
OUTPUT_PNG="$USER_DESKTOP/incident_management.png"

rm -f "$OUTPUT_FILE" "$OUTPUT_PNG" 2>/dev/null || true

# 2. Create the Process Specification File (Real ITIL v4 Content)
cat > "$SPEC_FILE" << 'EOF'
ITIL v4 Incident Management Process Specification
=================================================

OBJECTIVE:
Restore normal service operation as quickly as possible and minimize the adverse impact on business operations.

PARTICIPANTS (POOLS/LANES):
1. End User (External Participant)
2. Service Desk (Internal Pool) containing:
   - L1 Support (First Line)
   - L2 Support (Second Line / Technical Support)
   - Incident Manager (Process Owner)

PROCESS FLOW:

1. INCIDENT DETECTION & LOGGING
   - The process starts when an [End User] reports an issue (Message Flow).
   - [L1 Support] performs the "Log Incident" task (capture details).

2. CATEGORIZATION & PRIORITIZATION
   - [L1 Support] performs "Categorize & Prioritize" based on urgency and impact.

3. INITIAL DIAGNOSIS (L1)
   - Gateway: Is this a Known Error?
     - YES: [L1 Support] performs "Apply Known Fix". Proceed to Resolution.
     - NO: Gateway: Is it L1 Resolvable?
       - YES: [L1 Support] attempts resolution.
       - NO: Sequence flow moves to [L2 Support] lane.

4. INVESTIGATION & DIAGNOSIS (L2)
   - [L2 Support] performs "Investigate & Diagnose".
   - *Constraint*: Attach a Timer Event "SLA Breach Warning" to this task.
   - Gateway: Is this a Major Incident?
     - YES: Sequence flow moves to [Incident Manager] lane for "Escalate to Major Incident" task.
     - NO: Proceed to resolution.

5. RESOLUTION & RECOVERY
   - [L2 Support] (or L1) performs "Implement Resolution".
   - Gateway: Resolved?
     - NO: Loop back to Investigation.
     - YES: Proceed to Closure.

6. CLOSURE
   - [L1 Support] performs "Close Incident".
   - A notification (Message Flow) is sent back to the [End User].
   - Process ends at "Incident Closed" event.

DIAGRAMMING REQUIREMENTS:
- Use standard BPMN 2.0 notation.
- Use a "Pool" for Service Desk with 3 "Lanes".
- Use a collapsed "Pool" for End User.
- Use "Exclusive Gateways" (diamonds with X or blank) for decisions.
- Use "Sequence Flows" (solid lines) within the Service Desk pool.
- Use "Message Flows" (dashed lines) between End User and Service Desk.
EOF

chown ga:ga "$SPEC_FILE"
chmod 644 "$SPEC_FILE"
echo "Created specification file at $SPEC_FILE"

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch draw.io
# Using the standard launch command for the environment
DRAWIO_BIN="drawio"
if [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio"; fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# 5. Wait for window and set up
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss the "Create New / Open Existing" dialog to start with a blank canvas
# Pressing Escape usually cancels the dialog and leaves a blank diagram
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Verify application state
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running and ready."
else
    echo "WARNING: draw.io might not have started correctly."
fi

# 6. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="