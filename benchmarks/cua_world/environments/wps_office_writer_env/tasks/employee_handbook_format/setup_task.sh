#!/bin/bash
set -euo pipefail
echo "=== Setting up Employee Handbook Format Task ==="

source /workspace/scripts/task_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
sudo -u ga mkdir -p /home/ga/Documents/results

# Generate the realistic raw unformatted handbook document
python3 << 'PYEOF'
import os
from docx import Document
from docx.shared import Pt

doc = Document()

# Add all text sequentially as plain Normal text (unformatted)
paragraphs = [
    "2026 Employee Handbook",
    "Welcome to [Company Name]. We are thrilled to have you on board. This handbook is designed to serve as a comprehensive guide to our company policies, procedures, and expectations. Please read it carefully as it forms the basis of your employment relationship with us.",
    "1.0 Welcome and Introduction",
    "At [Company Name], we believe that our employees are our greatest asset. Our mission is to innovate healthcare solutions while fostering a collaborative, inclusive, and forward-thinking workplace.",
    "1.1 Core Values",
    "Integrity, Innovation, and Inclusion form the foundation of [Company Name]. We expect all employees to embody these values in their daily work, interactions with colleagues, and engagement with our clients and partners. We strive to maintain the highest standards of professional conduct.",
    "2.0 Employment Policies",
    "This section outlines the fundamental policies governing your employment at [Company Name]. These policies are designed to ensure a safe, fair, and productive work environment for everyone.",
    "2.1 Equal Employment Opportunity",
    "[Company Name] provides equal employment opportunities to all employees and applicants for employment without regard to race, color, religion, sex, national origin, age, disability, or genetics. This policy applies to all terms and conditions of employment, including recruiting, hiring, placement, promotion, termination, layoff, recall, transfer, leaves of absence, compensation, and training.",
    "2.2 At-Will Employment",
    "Your employment with [Company Name] is 'at-will'. This means that either you or [Company Name] may terminate the employment relationship at any time, with or without cause, and with or without advance notice. No manager or representative of [Company Name] has the authority to enter into any agreement for employment for any specified period of time or to make any agreement contrary to the at-will policy.",
    "3.0 Compensation and Benefits",
    "[Company Name] is committed to providing competitive compensation and a comprehensive benefits package to support the health and well-being of our employees and their families.",
    "3.1 Paid Time Off (PTO)",
    "Eligible employees at [Company Name] accrue PTO based on their length of service. PTO can be used for vacation, personal time, or illness. All PTO requests must be approved in advance by your direct supervisor, except in cases of unexpected illness or emergency.",
    "3.2 Health Insurance",
    "[Company Name] offers comprehensive health, dental, and vision insurance plans for all full-time employees. Coverage begins on the first day of the month following your hire date. Please consult the Benefits Guide for detailed information on plan options and enrollment deadlines.",
    "4.0 Code of Conduct and Ethics",
    "All employees are expected to conduct themselves in a professional manner that reflects positively on [Company Name]. We do not tolerate unethical behavior, conflict of interest, or illegal activities.",
    "4.1 Workplace Safety",
    "[Company Name] is committed to providing a safe and healthy work environment. Employees must comply with all safety and health requirements, whether established by [Company Name] or by federal, state, or local laws.",
    "4.2 Anti-Harassment Policy",
    "[Company Name] strictly prohibits any form of unlawful employee harassment based on race, color, religion, gender, sexual orientation, national origin, age, disability, or veteran status. Any employee who violates this policy will be subject to disciplinary action, up to and including termination.",
    "5.0 Acknowledgment",
    "I acknowledge that I have received, read, and understand the policies outlined in the [Company Name] Employee Handbook. I understand that [Company Name] reserves the right to modify, revoke, suspend, terminate, or change any or all such plans, policies, or procedures, in whole or in part, at any time with or without notice."
]

for text in paragraphs:
    p = doc.add_paragraph(text)

doc.save("/home/ga/Documents/handbook_draft_raw.docx")
os.chown("/home/ga/Documents/handbook_draft_raw.docx", 1000, 1000)
PYEOF

# Ensure WPS Writer is not already running
pkill -f "wps" || true
sleep 1

# Launch WPS Writer directly opening the raw document
echo "Starting WPS Office Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/handbook_draft_raw.docx > /tmp/wps_launch.log 2>&1 &"

# Wait for WPS Writer to open
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -i "handbook_draft_raw"; then
        echo "WPS Writer window detected"
        break
    fi
    sleep 1
done

# Focus and Maximize the window
DISPLAY=:1 wmctrl -a "handbook_draft_raw" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "handbook_draft_raw" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs (like EULA) using xdotool
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="