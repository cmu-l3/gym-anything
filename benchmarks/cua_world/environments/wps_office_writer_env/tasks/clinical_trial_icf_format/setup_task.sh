#!/bin/bash
set -euo pipefail

echo "=== Setting up Clinical Trial ICF Format Task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Load standard task utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Prepare directories
sudo -u ga mkdir -p /home/ga/Documents

# Use python-docx to generate the starting draft document
python3 << 'PYEOF'
import os
try:
    from docx import Document
except ImportError:
    import subprocess
    import sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "python-docx"])
    from docx import Document

doc = Document()

# Add Title block (unformatted)
doc.add_paragraph("INFORMED CONSENT FORM: Phase II Trial of ONC-2026 for Advanced Solid Tumors")
doc.add_paragraph("Principal Investigator: Dr. Eleanor Vance, MD, PhD")
doc.add_paragraph("Sponsor: Global Pharma Therapeutics Inc.")
doc.add_paragraph("")

doc.add_paragraph("Introduction")
doc.add_paragraph("You are being asked to participate in a clinical research study. This document provides important information about what you will be asked to do during the study, the risks and benefits, and your rights as a research participant. Please read this form carefully and ask any questions you may have before deciding whether to participate.")

doc.add_paragraph("Purpose of the Research")
doc.add_paragraph("The purpose of this study is to test the safety and effectiveness of an investigational drug, ONC-2026, in patients with advanced solid tumors. We hope to learn if this new medication can help shrink tumors or stop them from growing, and to understand what side effects it may cause.")

doc.add_paragraph("Study Procedures")
doc.add_paragraph("If you agree to participate, you will be in this study for approximately 12 months. You will need to visit the clinic every 3 weeks. During these visits, we will collect blood samples, perform physical exams, and you will receive an intravenous (IV) infusion of the study drug. CT scans will be performed every 9 weeks to measure your tumor.")

doc.add_paragraph("Risks and Discomforts")
doc.add_paragraph("There are risks to taking part in this research study. The known risks of the study medication include nausea, severe fatigue, mild dizziness, and temporary injection site swelling. You may also experience discomfort or bruising from blood draws. There may be other risks that are currently unknown.")

doc.add_paragraph("Potential Benefits")
doc.add_paragraph("You may or may not benefit directly from participating in this study. The study drug may shrink your tumor or stop it from growing, but this is not guaranteed. The information learned from this study may help future patients with advanced solid tumors.")

doc.add_paragraph("Confidentiality")
doc.add_paragraph("Your medical and research records will be kept confidential to the extent permitted by law. We will assign a code to your records, and your name will not be used in any reports or publications resulting from this study. Representatives of the IRB, the sponsor, and regulatory agencies like the FDA may review your records to ensure the study is being conducted properly.")

doc.add_paragraph("Voluntary Participation")
doc.add_paragraph("Your participation in this research is entirely voluntary. It is your choice whether to participate or not. If you choose not to participate, all the services you receive at this clinic will continue and nothing will change. You may change your mind later and stop participating even if you agreed earlier.")

doc.add_paragraph("Contact Information")
doc.add_paragraph("If you have any questions about the study, or if you experience a research-related injury, please contact Dr. Eleanor Vance at 555-0198. If you have questions about your rights as a research participant, please contact the Institutional Review Board (IRB) at 555-0200.")

doc.save("/home/ga/Documents/draft_icf.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/draft_icf.docx
sudo chmod 644 /home/ga/Documents/draft_icf.docx

# Ensure no stale target file exists
rm -f /home/ga/Documents/final_icf_v2.docx 2>/dev/null || true

# Allow local X11 connections
xhost +local: 2>/dev/null || true

# Start WPS Writer if not running
if ! pgrep -f "wps" > /dev/null; then
    echo "Starting WPS Writer..."
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/draft_icf.docx > /dev/null 2>&1 &"
    
    # Wait for the window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "wps"; then
            echo "Application window detected."
            break
        fi
        sleep 1
    done
fi

sleep 3

# Maximize and Focus window
wid=$(DISPLAY=:1 wmctrl -l | grep -i "wps" | awk '{print $1}' | head -1)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss possible startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="