#!/bin/bash
# setup_task.sh for chest_pain_triage_flowchart
set -e

echo "=== Setting up Chest Pain Triage Task ==="

# 1. Create the input text file with the clinical algorithm
cat > /home/ga/Desktop/chest_pain_pathway.txt << 'EOF'
AHA/ACC 2021 CHEST PAIN EVALUATION PATHWAY
==========================================

START: Patient presents to ED with Acute Chest Pain

STEP 1: INITIAL ASSESSMENT
- Perform ECG within 10 minutes.
- DECISION: Is there ST-Elevation?
  - YES: Activate Cath Lab (STEMI Protocol) -> HIGH RISK (RED)
  - NO: Continue to Step 2.

STEP 2: BIOMARKERS (TROPONIN)
- Measure High-Sensitivity Troponin (0h and 1h/2h).
- DECISION: Is Troponin Elevated or Rising?
  - YES: Consult Cardiology (NSTEMI/ACS) -> HIGH RISK (RED)
  - NO: Continue to Step 3.

STEP 3: RISK STRATIFICATION (HEART SCORE)
- Calculate HEART Score (History, ECG, Age, Risk factors, Troponin).
- DECISION: What is the Risk Category?
  - LOW RISK (Score 0-3): Discharge with outpatient follow-up -> LOW RISK (GREEN)
  - MODERATE RISK (Score 4-6): Admit to Observation Unit for Stress Testing -> MODERATE RISK (ORANGE)
  - HIGH RISK (Score 7-10): Admit for Angiography -> HIGH RISK (RED)

REFERENCE: HEART SCORE COMPONENTS (0-2 points each)
1. History (Slightly suspicious / Moderately suspicious / Highly suspicious)
2. ECG (Normal / Non-specific / ST depression)
3. Age (<45 / 45-65 / >65)
4. Risk Factors (None / 1-2 / >=3)
5. Troponin (Normal / 1-3x limit / >3x limit)
EOF

chown ga:ga /home/ga/Desktop/chest_pain_pathway.txt
chmod 644 /home/ga/Desktop/chest_pain_pathway.txt

# 2. Record start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Clean up any previous run artifacts
rm -f /home/ga/Desktop/chest_pain_triage.drawio
rm -f /home/ga/Desktop/chest_pain_triage.png

# 4. Launch draw.io Desktop
# We use a helper script or direct launch. The env setup script creates a wrapper,
# but we call the binary directly to ensure we control flags.
echo "Launching draw.io..."
if command -v drawio &>/dev/null; then
    CMD="drawio"
elif [ -f /opt/drawio/drawio ]; then
    CMD="/opt/drawio/drawio"
else
    CMD="/usr/bin/drawio"
fi

# Launch in background as user 'ga'
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $CMD --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# 5. Wait for window and handle startup dialog
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5 # Wait for UI to fully render

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss the "Create New / Open Existing" dialog (Esc creates a blank diagram)
DISPLAY=:1 xdotool key Escape
sleep 2

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="