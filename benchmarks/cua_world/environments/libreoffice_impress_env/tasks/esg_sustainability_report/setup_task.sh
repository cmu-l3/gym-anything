#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up ESG Sustainability Report Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Real ESG metrics data from Apple Inc. Environmental Progress Report 2023
# Source: https://www.apple.com/environment/pdf/Apple_Environmental_Progress_Report_2023.pdf
sudo -u ga tee /home/ga/Documents/Presentations/esg_metrics_2022.csv > /dev/null << 'CSVEOF'
Metric,Category,2020,2021,2022,Unit,Notes
Market-Based Scope 1 & 2 Emissions,Environmental,0,0,0,MT CO2e,Carbon neutral since 2020
Scope 3 Product Lifecycle Emissions,Environmental,22.6,23.5,20.6,Million MT CO2e,Includes manufacturing & use
Total Electricity Use,Environmental,1038,1098,1302,GWh,All operations worldwide
Renewable Energy Percentage,Environmental,100,100,100,Percent,100% renewable since 2018
Total Operational Water Use,Environmental,10.3,11.7,10.3,Million Gallons,Facilities
Water Recycled or Reused,Environmental,61,63,71,Percent,Of total water consumed
Waste Diversion Rate from Landfill,Environmental,72,78,81,Percent,Operations
Manufacturing Waste Generated,Environmental,75219,91280,113900,Metric Tons,Total
Women in Global Workforce,Social,35,35,37,Percent,
Underrepresented Groups in US Workforce,Social,50,53,54,Percent,
Supplier RMAP Responsible Assessments,Social,1184,1196,1236,Count,Supplier audits
Pay Equity Audits Completed,Governance,Yes,Yes,Yes,Boolean,Annual
Independent Board Directors,Governance,8,8,8,Count,Of 9 total directors
CSVEOF

# Create the 4-slide draft ODP
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
add_slide(doc, "2022 ESG Sustainability Report", [
    "Environmental · Social · Governance",
    "Annual Stakeholder Report — DRAFT",
    "Data: FY2022 (Calendar Year)",
])

# Slide 2: KPI Overview (incomplete placeholder)
add_slide(doc, "Key ESG Performance Indicators", [
    "[See esg_metrics_2022.csv for complete data]",
    "Environmental: Scope 1+2 emissions, Energy, Water, Waste",
    "Social: Workforce diversity, Supplier audits, Pay equity",
    "Governance: Board independence, Ethics, Transparency",
    "[ADD CHARTS FOR EACH CATEGORY]",
])

# Slide 3: Environmental highlights (stub)
add_slide(doc, "Environmental Performance", [
    "[PLACEHOLDER — Expand with data from CSV]",
    "Topics to cover: Carbon neutrality, Renewable energy, Water stewardship, Waste",
    "[ADD TREND CHART]",
])

# Slide 4: Looking Forward
add_slide(doc, "2030 Goals & Commitments", [
    "Carbon neutral across entire supply chain by 2030",
    "100% recycled or renewable materials in products",
    "Zero waste to landfill in all facilities",
    "[EXPAND THIS SLIDE — ADD SOCIAL AND GOVERNANCE GOALS]",
])

doc.save("/home/ga/Documents/Presentations/esg_report_2022.odp")
print("4-slide ESG report draft created")
PYEOF

sudo chown -R ga:ga /home/ga/Documents/Presentations/

# Record baseline
echo "4" > /tmp/esg_initial_slides
echo "0" > /tmp/esg_initial_charts
date +%s > /tmp/task_start_timestamp

su - ga -c "DISPLAY=:1 scrot /tmp/task_start_screenshot.png" || true

# Launch LibreOffice Impress
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/esg_report_2022.odp > /tmp/impress_esg.log 2>&1 &"

wait_for_process "soffice" 20
wait_for_window "LibreOffice Impress" 90

sleep 2
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== ESG Sustainability Report Task Setup Complete ==="
echo "Data: /home/ga/Documents/Presentations/esg_metrics_2022.csv"
echo "Draft: /home/ga/Documents/Presentations/esg_report_2022.odp (4 slides)"
echo "Goal: Complete 10-slide ESG report with 3+ charts, 6+ notes, 8+ transitions, PDF export"
