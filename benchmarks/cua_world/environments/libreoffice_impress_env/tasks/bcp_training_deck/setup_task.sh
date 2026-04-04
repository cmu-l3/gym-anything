#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up BCP Training Deck Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the 6-slide BCP draft using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P

doc = OpenDocumentPresentation()

def add_slide(doc, title_text, bullets=None):
    idx = len(doc.presentation.childNodes) + 1
    page = Page(name=f"Slide{idx}")
    doc.presentation.addElement(page)

    tf = Frame(width="24cm", height="3cm", x="2cm", y="0.8cm")
    page.addElement(tf)
    tb = TextBox()
    tf.addElement(tb)
    tb.addElement(P(text=title_text))

    if bullets:
        cf = Frame(width="24cm", height="13cm", x="2cm", y="4.2cm")
        page.addElement(cf)
        cb = TextBox()
        cf.addElement(cb)
        for b in bullets:
            cb.addElement(P(text=b))
    return page

# Slide 1: Title
add_slide(doc, "Business Continuity Plan — Employee Training", [
    "Understanding Your Role in Organizational Resilience",
    "Based on ISO 22301:2019 and FEMA BCP Guidelines",
    "Annual Mandatory Training — All Staff",
])

# Slide 2: Training Objectives
add_slide(doc, "Training Objectives", [
    "Understand what a Business Continuity Plan is and why it matters",
    "Know your specific role during a business disruption",
    "Be able to locate and access BCP documentation",
    "Understand escalation paths and decision authorities",
    "Know RTO/RPO targets for your department",
])

# Slide 3: Business Impact Analysis Overview
add_slide(doc, "Business Impact Analysis (BIA)", [
    "BIA identifies critical business functions and their dependencies",
    "Tier 1 (Critical): Customer-facing systems — RTO 4 hours, RPO 1 hour",
    "Tier 2 (Essential): Internal operations — RTO 24 hours, RPO 4 hours",
    "Tier 3 (Important): Administrative — RTO 72 hours, RPO 24 hours",
    "Tier 4 (Deferrable): Non-time-sensitive — RTO 7 days, RPO 7 days",
    "[ADD RTO/RPO COMPARISON CHART]",
])

# Slide 4: Recovery Strategies
add_slide(doc, "Recovery Strategies & Alternate Sites", [
    "Hot site: Fully operational backup facility — activated within 1 hour",
    "Warm site: Partially configured — operational within 4 hours",
    "Cold site: Basic infrastructure — operational within 24 hours",
    "Cloud DR: AWS/Azure failover — automated, within 15 minutes for Tier 1",
    "Work from home: For eligible roles, no physical site required",
])

# Slide 5: Emergency Response — PLACEHOLDER (agent must create flowchart)
add_slide(doc, "Emergency Response Process", [
    "[ADD EMERGENCY RESPONSE FLOWCHART HERE]",
    "The flowchart must show the complete incident response sequence:",
    "from initial detection through declaration, activation, recovery, and closure",
    "Use connected shapes to show the flow",
])

# Slide 6: Testing & Exercises
add_slide(doc, "BCP Testing & Exercise Schedule", [
    "Tabletop Exercise: Quarterly — Discuss scenario responses",
    "Functional Exercise: Semi-annual — Test specific recovery procedures",
    "Full-Scale Drill: Annual — End-to-end BCP activation simulation",
    "Results tracked in BCP Management System",
    "[EXPAND: Add more slides on communication plans, vendor contacts, etc.]",
])

doc.save("/home/ga/Documents/Presentations/bcp_training.odp")
print("6-slide BCP training draft created")
PYEOF

sudo chown -R ga:ga /home/ga/Documents/Presentations/

# Record baseline
echo "6" > /tmp/bcp_initial_slides
date +%s > /tmp/task_start_timestamp

su - ga -c "DISPLAY=:1 scrot /tmp/task_start_screenshot.png" || true

# Launch LibreOffice Impress
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/bcp_training.odp > /tmp/impress_bcp.log 2>&1 &"

wait_for_process "soffice" 20
wait_for_window "LibreOffice Impress" 90

sleep 2
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== BCP Training Deck Task Setup Complete ==="
echo "Draft: /home/ga/Documents/Presentations/bcp_training.odp (6 slides)"
echo "Goal: Complete 12-slide BCP training deck with flowchart (8+ shapes), RTO/RPO chart, 8+ notes, PDF"
