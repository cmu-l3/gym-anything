#!/bin/bash
# setup_task.sh for drug_interaction_research

set -e

echo "=== Setting up Drug Interaction Research Task ==="

# 1. Kill Edge to ensure clean start
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 3. Clean up previous artifacts
rm -f "/home/ga/Desktop/drug_interaction_report.txt"
rm -f "/home/ga/Desktop/patient_medications.txt"
# Note: We don't wipe downloads/bookmarks completely to simulate a persistent user environment, 
# but the verifier will check timestamps/diffs.

# 4. Create Patient Medication Briefing
cat > "/home/ga/Desktop/patient_medications.txt" << 'EOF'
PATIENT MEDICATION REVIEW REQUEST
==================================
Patient: #4782 (68-year-old male)
Current Medications:
  1. Warfarin 5mg daily (anticoagulant - prescribed for atrial fibrillation)
  2. Lisinopril 10mg daily (ACE inhibitor - prescribed for hypertension)
  3. Metformin 500mg twice daily (biguanide - prescribed for type 2 diabetes)

REQUEST: Please research potential drug-drug interactions between these
three medications using authoritative medical reference databases.
Compile findings into a safety report for pharmacist review.

DELIVERABLES:
1. Save report to: /home/ga/Desktop/drug_interaction_report.txt
2. Download relevant patient information sheets to: /home/ga/Downloads/
3. Bookmark key reference pages in a Favorites folder called "Patient Safety References"
EOF
chown ga:ga "/home/ga/Desktop/patient_medications.txt"
chmod 644 "/home/ga/Desktop/patient_medications.txt"

# 5. Launch Edge on a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# 6. Wait for Edge window
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window appeared."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# 7. Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="