#!/bin/bash
set -euo pipefail

echo "=== Setting up Engineering Change Notice Format Task ==="

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents

# Record task start time for anti-gaming verification
date +%s > /tmp/ecn_task_start_ts

# Generate the raw unstructured document using python-docx
python3 << 'PYEOF'
import os
try:
    from docx import Document
except ImportError:
    import subprocess
    subprocess.check_call(["pip3", "install", "python-docx"])
    from docx import Document

doc = Document()

# Add all data as unformatted prose
doc.add_paragraph("Draft Engineering Change Notice")
doc.add_paragraph("Metadata:")
doc.add_paragraph("ECN Number: ECN-2024-0847")
doc.add_paragraph("Date: 2024-11-15")
doc.add_paragraph("Revision: A")
doc.add_paragraph("Classification: Class II Medical Device")
doc.add_paragraph("Product: Endoscopic Grasping Forceps Model EGF-200")
doc.add_paragraph("Change: Substituting 17-4 PH stainless steel jaw inserts with Custom 455 stainless steel.")

doc.add_paragraph("")
doc.add_paragraph("Reason for Change")
doc.add_paragraph("Supplier discontinuation of 17-4 PH medical grade stock and requirement for improved corrosion resistance during repeated autoclave cycles.")

doc.add_paragraph("")
doc.add_paragraph("Description of Change")
doc.add_paragraph("Substitute existing 17-4 PH stainless steel jaw inserts with Custom 455 precipitation-hardened stainless steel. No changes to jaw geometry or mating surfaces.")

doc.add_paragraph("")
doc.add_paragraph("Affected Documents")
doc.add_paragraph("Doc Number: DS-EGF-200-003, Title: Jaw Insert Material Specification, Current Rev: C, New Rev: D, Action: Revise material callout")
doc.add_paragraph("Doc Number: MP-EGF-200-011, Title: Jaw Insert Machining Procedure, Current Rev: B, New Rev: C, Action: Update feeds/speeds")
doc.add_paragraph("Doc Number: VP-EGF-200-007, Title: IQ/OQ/PQ Validation Protocol, Current Rev: A, New Rev: B, Action: Add Custom 455 testing")
doc.add_paragraph("Doc Number: DHF-EGF-200-001, Title: Design History File Index, Current Rev: F, New Rev: G, Action: Add ECN reference")
doc.add_paragraph("Doc Number: RA-EGF-200-002, Title: Biocompatibility Risk Assessment, Current Rev: B, New Rev: C, Action: Reassess material")
doc.add_paragraph("Doc Number: LR-EGF-200-004, Title: FDA 510(k) Predicate Comparison, Current Rev: A, New Rev: B, Action: Update material section")

doc.add_paragraph("")
doc.add_paragraph("Impact Assessment")
doc.add_paragraph("Category: Quality, Level: Positive, Description: Improved corrosion resistance and edge retention.")
doc.add_paragraph("Category: Regulatory, Level: Moderate, Description: Requires Letter to File, no new 510(k) needed.")
doc.add_paragraph("Category: Safety, Level: Neutral-Positive, Description: Material has established biocompatibility profile.")
doc.add_paragraph("Category: Cost, Level: Minor Negative, Description: Custom 455 raw material is 12% more expensive.")

doc.add_paragraph("")
doc.add_paragraph("Risk Assessment")
doc.add_paragraph("Risk Factor: Material Performance, Likelihood: Low, Severity: High, Risk Level: Medium")
doc.add_paragraph("Risk Factor: Regulatory Compliance, Likelihood: Medium, Severity: Medium, Risk Level: Medium")
doc.add_paragraph("Risk Factor: Supply Chain, Likelihood: Low, Severity: Low, Risk Level: Low")

doc.add_paragraph("")
doc.add_paragraph("Implementation Plan")
doc.add_paragraph("Phase 1: Prototype Fabrication & Testing, Owner: Materials Engineering, Target Date: 2025-01-15, Status: Not Started")
doc.add_paragraph("Phase 2: First Article Inspection, Owner: Quality Assurance, Target Date: 2025-02-28, Status: Not Started")
doc.add_paragraph("Phase 3: Validation Protocol Execution (IQ/OQ/PQ), Owner: Validation Engineering, Target Date: 2025-04-15, Status: Not Started")
doc.add_paragraph("Phase 4: Regulatory Submission Update, Owner: Regulatory Affairs, Target Date: 2025-05-30, Status: Not Started")
doc.add_paragraph("Phase 5: Production Transition, Owner: Manufacturing, Target Date: 2025-07-01, Status: Not Started")

doc.add_paragraph("")
doc.add_paragraph("Approval Signatures")
doc.add_paragraph("Role: Originator, Name: Sarah Chen")
doc.add_paragraph("Role: Engineering Manager, Name: David Park")
doc.add_paragraph("Role: Quality Manager, Name: Maria Rodriguez")
doc.add_paragraph("Role: Regulatory Affairs, Name: James Liu")
doc.add_paragraph("Role: VP Operations, Name: Karen Mitchell")

doc.save("/home/ga/Documents/ECN-2024-0847_draft.docx")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/ECN-2024-0847_draft.docx
chmod 644 /home/ga/Documents/ECN-2024-0847_draft.docx

# Start WPS Writer with the document
echo "Starting WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/ECN-2024-0847_draft.docx > /dev/null 2>&1 &"

# Wait for application window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "WPS Writer\|ECN-2024-0847_draft"; then
        break
    fi
    sleep 1
done

# Maximize and focus window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "WPS Writer\|ECN-2024-0847_draft" | awk '{print $1}' | head -1 || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
# Try to dismiss any initial welcome dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/ecn_task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="