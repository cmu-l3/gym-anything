#!/bin/bash
set -u

echo "=== Setting up medical_genogram_huntingtons task ==="

# 1. Create the Patient Interview Transcript
cat > /home/ga/Desktop/patient_interview.txt << 'EOF'
CLINICAL INTAKE NOTES
Patient: Alice V.
Reason for Referral: Family history of Huntington's Disease (HD).

FAMILY HISTORY:
The patient (Alice) is a 35-year-old female. She is currently asymptomatic but is anxious about her risk. She has not yet undergone genetic testing.

Generation I (Paternal Grandparents):
- Grandfather: Arthur. Diagnosed with HD in his 40s. Deceased at age 62.
- Grandmother: Betty. No history of neurological disease. Deceased at age 85 (natural causes).

Generation II (Parents & Siblings):
- Father: Charles (Arthur's son). Currently 60 years old. He was diagnosed with HD five years ago and is symptomatic.
- Mother: Diana. 58 years old. Living and well. No family history of HD.
- Uncle: Edward (Charles's younger brother). 55 years old. Living and well. No symptoms.

Generation III (Patient's Generation):
- Patient: Alice (see above).
- Brother: Frank. 32 years old. Living and well. No symptoms reported.
EOF

chown ga:ga /home/ga/Desktop/patient_interview.txt
chmod 644 /home/ga/Desktop/patient_interview.txt

# 2. Clean up previous runs
rm -f /home/ga/Desktop/genogram.drawio
rm -f /home/ga/Desktop/genogram.png

# 3. Record start time and initial state
date +%s > /tmp/task_start_time.txt

# 4. Launch draw.io
# Find binary
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

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Wait for UI load
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Esc creates blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="