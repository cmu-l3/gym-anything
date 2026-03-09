#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Cloud Migration Repair Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the 9-slide cloud migration deck with intentional errors using python-pptx
# (python-pptx is installed in VM; we save as PPTX then open LibreOffice for editing,
# but to avoid format dialogs we generate ODP directly via odfpy instead)
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P

doc = OpenDocumentPresentation()

def add_slide(doc, title_text, bullets=None):
    idx = len(doc.presentation.childNodes) + 1
    page = Page(name=f"Slide{idx}")
    doc.presentation.addElement(page)

    # Title frame
    tf = Frame(width="24cm", height="3cm", x="2cm", y="0.8cm")
    page.addElement(tf)
    tb = TextBox()
    tf.addElement(tb)
    tb.addElement(P(text=title_text))

    # Content frame
    if bullets:
        cf = Frame(width="24cm", height="13cm", x="2cm", y="4.2cm")
        page.addElement(cf)
        cb = TextBox()
        cf.addElement(cb)
        for b in bullets:
            cb.addElement(P(text=b))
    return page

# Slide 1: Title slide
add_slide(doc, "Cloud Migration Project – Phase 2 Execution", [
    "IT Infrastructure Team",
    "Prepared: Q1 2024",
    "Confidential – Internal Use Only",
])

# Slide 2: Executive Summary
add_slide(doc, "Executive Summary", [
    "Migration of 147 legacy applications to hybrid cloud environment",
    "Total project budget: $2.4 million",
    "Timeline: 18 months (Q1 2024 – Q2 2025)",
    "Scope: Azure IaaS + AWS S3 data tier",
    "Current status: Phase 1 complete, Phase 2 in progress",
])

# Slide 3: Technical Infrastructure Overview — contains deliberate TYPO "Infrastrucutre"
add_slide(doc, "Technical Infrastrucutre Overview", [
    "Current environment: On-premise data center (Chicago HQ)",
    "Server count: 96 physical servers",
    "Virtual machines in scope: 241 VMs",
    "Primary workloads: ERP, CRM, Document Management",
    "Network bandwidth upgrade: 10Gbps dedicated line provisioned",
    "Hybrid connectivity: ExpressRoute + Site-to-Site VPN",
])

# Slide 4: Migration Timeline
add_slide(doc, "Migration Timeline & Milestones", [
    "Q1 2024 – Discovery & Assessment: Dependency mapping complete",
    "Q2 2024 – Wave 1: Dev/test environments (32 VMs)",
    "Q3 2024 – Wave 2: Non-critical production workloads (89 VMs)",
    "Q4 2024 – Wave 3: Core business applications (78 VMs)",
    "Q1 2025 – Wave 4: ERP & data warehouse cutover",
    "Q2 2025 – Decommission and final validation",
])

# Slide 5: Cost Analysis
add_slide(doc, "Cost Analysis & Budget Tracking", [
    "Phase 1 spend: $480,000 (budget: $500,000) — UNDER BUDGET",
    "Phase 2 estimate: $820,000",
    "Azure annual run rate (post-migration): $340,000",
    "On-premise cost avoided (Year 1): $610,000",
    "3-year TCO savings projection: $1.2M",
    "Contingency reserve: $180,000 (7.5%)",
])

# Slide 6: Security Overview — INTENTIONALLY EMPTY (agent must fill this in)
add_slide(doc, "Security Overview", [])

# Slide 7: Risk Assessment
add_slide(doc, "Risk Assessment & Mitigation", [
    "Risk 1 (HIGH): Data loss during cutover — Mitigation: Parallel run + rollback plan",
    "Risk 2 (HIGH): Application compatibility — Mitigation: Pre-migration testing in UAT",
    "Risk 3 (MED): Staff skill gaps — Mitigation: Azure/AWS training program Q1 2024",
    "Risk 4 (MED): Vendor lock-in — Mitigation: Multi-cloud architecture with abstraction layer",
    "Risk 5 (LOW): Network latency — Mitigation: Performance benchmarking prior to cutover",
])

# Slide 8: Team Structure
add_slide(doc, "Project Team Structure", [
    "Project Sponsor: CTO Sarah Chen",
    "Project Manager: DevOps Lead (TBD)",
    "Cloud Architect: External Consultant (Accenture)",
    "Security Lead: InfoSec team (2 FTE)",
    "Application Owners: Dept heads for each wave",
    "Operations: 3 FTE + 1 contractor",
])

# Slide 9: Next Steps
add_slide(doc, "Next Steps & Action Items", [
    "ACTION: Finalize Wave 2 application dependency map by Jan 31",
    "ACTION: Complete security control documentation for Cloud CISO review",
    "ACTION: Schedule stakeholder briefing for Q2 cutover planning",
    "ACTION: Confirm Azure ExpressRoute bandwidth upgrade completion",
    "ACTION: Publish updated project charter to SharePoint",
    "Next review: Steering Committee Feb 15, 2024",
])

doc.save("/home/ga/Documents/Presentations/cloud_migration_deck.odp")
print("9-slide cloud migration deck created with intentional errors")
PYEOF

sudo chown -R ga:ga /home/ga/Documents/Presentations/

# Record baseline state
echo "9" > /tmp/cloud_migration_initial_slides
echo "0" > /tmp/cloud_migration_initial_notes
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_start_screenshot.png" || true

# Launch LibreOffice Impress
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/cloud_migration_deck.odp > /tmp/impress_cloud.log 2>&1 &"

wait_for_process "soffice" 20
wait_for_window "LibreOffice Impress" 90

sleep 2
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Cloud Migration Repair Task Setup Complete ==="
echo "File: /home/ga/Documents/Presentations/cloud_migration_deck.odp"
echo "Errors to fix: typo in slide 3 title, empty Security Overview slide, no notes, no transitions"
