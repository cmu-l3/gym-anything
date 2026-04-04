#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up ESI Triage Decision Tree Task ==="

# 1. Create the Algorithm Reference File
cat > /home/ga/Desktop/esi_v4_algorithm.txt << 'EOF'
EMERGENCY SEVERITY INDEX (ESI) VERSION 4 — TRIAGE ALGORITHM
============================================================
Source: AHRQ Publication No. 12-0014

DECISION POINT A:
  Question: "Does this patient require immediate lifesaving intervention?"
  Interventions include: intubation, surgical airway, emergency medication,
  hemodynamic interventions (fluid resuscitation, blood, pressors),
  procedural sedation, electrical therapy (defibrillation, cardioversion, pacing)
  → YES → Assign ESI Level 1 (Immediate / Resuscitation) [Color: RED]
  → NO  → Proceed to Decision Point B

DECISION POINT B:
  Question: "Is this a high-risk situation?"
  "OR is the patient confused, lethargic, or disoriented?"
  "OR is the patient in severe pain or distress?"
  High-risk includes: chest pain, stroke symptoms, suicidal ideation, etc.
  → YES → Assign ESI Level 2 (Emergent) [Color: ORANGE]
  → NO  → Proceed to Decision Point C

DECISION POINT C:
  Question: "How many different types of resources will this patient need?"
  Resources include: labs, ECG, X-rays, CT/MRI, IV fluids, IV meds, specialty consult.
  Do NOT count: history/physical, PO meds, tetanus shot, refill.
  → NONE (0 resources)   → Assign ESI Level 5 (Non-Urgent) [Color: BLUE]
  → ONE (1 resource)     → Assign ESI Level 4 (Less Urgent) [Color: GREEN]
  → TWO OR MORE (≥2)     → Proceed to Decision Point D

DECISION POINT D:
  Question: "Are vital signs in the danger zone?"
  (HR >100, RR >20, SaO2 <92% for adults)
  → YES → Consider upgrading to ESI Level 2 (Emergent)
  → NO  → Assign ESI Level 3 (Urgent) [Color: YELLOW]

SUMMARY OF LEVELS:
  Level 1: Resuscitation (Red)
  Level 2: Emergent (Orange)
  Level 3: Urgent (Yellow)
  Level 4: Less Urgent (Green)
  Level 5: Non-Urgent (Blue)
EOF

chown ga:ga /home/ga/Desktop/esi_v4_algorithm.txt
echo "Created algorithm reference file."

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous runs
rm -f /home/ga/Desktop/esi_triage_tree.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/esi_triage_tree.png 2>/dev/null || true

# 4. Launch draw.io Desktop
echo "Launching draw.io..."
# We use a helper script if available, or call binary directly
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio";
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio";
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"; fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

# Launch in background as user 'ga'
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# 5. Wait for Window and Maximize
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected."
        break
    fi
    sleep 1
done

sleep 3
# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 6. Dismiss Startup Dialog (New Diagram)
# The default startup dialog asks to Create New or Open Existing.
# Pressing 'Escape' usually closes the dialog and leaves a blank canvas or basic view.
# Alternatively, clicking "Create New Diagram" (if accessible via keybinds) is safer,
# but Escape is the standard "just let me draw" action.
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Ensure window is focused again
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Initial setup complete."