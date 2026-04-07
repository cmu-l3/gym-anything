#!/bin/bash
# Setup for pebl_visual_search_task_design task
# Places a detailed specification file on the Desktop
# Agent must find, read, and implement it as a PEBL script

set -e
echo "=== Setting up pebl_visual_search_task_design task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/tasks/visual_search
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/pebl
chown ga:ga /home/ga/Desktop

# Write the specification file to the Desktop (agent must discover this)
cat > /home/ga/Desktop/visual_search_spec.txt << 'SPECEOF'
VISUAL SEARCH EXPERIMENT — IMPLEMENTATION SPECIFICATION
CMU Department of Psychology | Course: 85-211 Perception & Attention
Prepared by: Prof. J. Miller | Revised: 2024-01-15

PARADIGM OVERVIEW
-----------------
Implement the Treisman & Gelade (1980) visual search paradigm using PEBL.
This experiment tests the Feature Integration Theory by comparing search
efficiency across two search types: feature search (pop-out) and conjunction search.

EXPERIMENT DESIGN
-----------------
Search Types (2):
  - "feature":     Target is defined by a single distinguishing feature
                   (color only). Target = RED circle among BLUE circles.
  - "conjunction": Target is defined by a conjunction of two features
                   (color AND shape). Target = RED circle among BLUE circles
                   and RED squares.

Target Presence (2):
  - "present": Target is present in the display
  - "absent":  Target is absent (only distractors)

Set Sizes (3):
  3, 8, 16 items total (including target if present)

Trial Structure:
  1. Fixation cross displayed for exactly 500 ms
  2. Search display shown for maximum 3000 ms (response ends display early)
  3. Inter-trial interval (blank screen) for exactly 800 ms
  4. Feedback: brief tone or text for 300 ms (optional but recommended)

Items:
  - Shapes: circles and squares
  - Colors: red and blue
  - Size: all items equal (~40x40 pixels recommended)
  - Arrangement: random positions within a central display region (avoid edges)

RESPONSE MAPPING
----------------
  z key  = TARGET PRESENT
  / key  = TARGET ABSENT
  No response within 3000ms = recorded as missed (RT = 3000, correct = 0)

TRIAL COUNTS
------------
  Practice block: 12 trials (balanced across conditions)
  Test blocks: 2 blocks x 48 trials each = 96 test trials
  Total condition repetitions per block:
    2 search types x 2 target presence x 3 set sizes = 12 conditions
    x 4 repetitions per block = 48 trials per block

DATA OUTPUT
-----------
Save data to: ~/pebl/data/visual_search/{subject_id}_session_{session}.csv
Columns: subject, session, block, trial, search_type, set_size, target_present,
         rt_ms, correct, response_key

PARTICIPANT INPUT
-----------------
Prompt for: Subject ID (text), Session number (integer)
These are passed as command-line arguments or prompted at startup.

NOTES FOR IMPLEMENTATION
------------------------
- Use PEBL's built-in random positioning; ensure items do not overlap
- The script must be completable in a terminal using: run-pebl visual_search_task.pbl
- Include clear instructions on screen before the practice block
- After practice, show accuracy feedback before test blocks begin
- The script can be exited early by pressing Escape (handle gracefully)

SPECEOF

chown ga:ga /home/ga/Desktop/visual_search_spec.txt
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x38 -- bash -c '
echo \"=== Visual Search Task Design ===\"
echo \"\"
echo \"Spec file:   ~/Desktop/visual_search_spec.txt\"
echo \"Output:      ~/pebl/tasks/visual_search/visual_search_task.pbl\"
echo \"Rationale:   ~/pebl/tasks/visual_search/design_rationale.txt\"
echo \"\"
echo \"Steps:\"
echo \"  1. Read the specification file on the Desktop\"
echo \"  2. Write a PEBL script implementing the spec\"
echo \"  3. Run: run-pebl ~/pebl/tasks/visual_search/visual_search_task.pbl\"
echo \"  4. Write design_rationale.txt\"
echo \"\"
bash' > /tmp/visual_search_terminal.log 2>&1 &"

# Wait for terminal
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== pebl_visual_search_task_design setup complete ==="
echo "Spec file placed at: /home/ga/Desktop/visual_search_spec.txt"
echo "Expected output: /home/ga/pebl/tasks/visual_search/visual_search_task.pbl"
