#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Board Strategy Review Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Real macroeconomic data from IMF World Economic Outlook October 2023
# Source: https://www.imf.org/en/Publications/WEO/Issues/2023/10/10/world-economic-outlook-october-2023
sudo -u ga tee /home/ga/Documents/Presentations/world_economic_data.csv > /dev/null << 'CSVEOF'
Region,GDP_Growth_2020_Pct,GDP_Growth_2021_Pct,GDP_Growth_2022_Pct,GDP_Growth_2023F_Pct,GDP_Growth_2024F_Pct
World,-3.0,6.0,3.4,3.0,3.2
Advanced Economies,-4.5,5.2,2.7,1.5,1.8
United States,-2.8,5.9,2.1,2.1,1.5
Euro Area,-6.1,5.3,3.5,0.7,1.2
Japan,-4.3,2.1,1.0,2.0,1.0
United Kingdom,-11.0,7.6,4.1,-0.3,0.6
Canada,-5.1,4.6,3.4,1.3,1.6
Emerging & Developing Economies,-2.0,6.8,3.9,4.0,4.1
China,2.2,8.4,3.0,5.0,4.2
India,-6.6,8.7,7.2,5.9,6.3
Brazil,-3.9,4.6,2.9,2.1,1.5
Russia,-2.7,5.6,2.1,2.2,1.1
Middle East & North Africa,-3.2,5.7,5.8,2.0,3.8
Sub-Saharan Africa,-1.7,4.5,3.9,3.5,4.1
Latin America & Caribbean,-7.0,6.9,3.9,2.3,2.3
CSVEOF

# Create the 5-slide stub ODP
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
add_slide(doc, "FY2024 Strategic Review — Board of Directors", [
    "Annual Strategy and Performance Review",
    "Confidential — Board Use Only",
    "Q1 2024 Board Meeting",
])

# Slide 2: Macroeconomic Context (placeholder)
add_slide(doc, "Global Macroeconomic Context", [
    "[See world_economic_data.csv for IMF WEO October 2023 projections]",
    "Global growth moderating: 3.4% in 2022 → 3.0% projected 2023",
    "Advanced economies softening; emerging markets showing resilience",
    "[ADD GDP GROWTH TREND CHART]",
    "[ADD REGIONAL COMPARISON CHART]",
])

# Slide 3: Strategic Priorities (stub — needs diagram)
add_slide(doc, "FY2024 Strategic Priorities", [
    "[ADD STRATEGIC PRIORITIES DIAGRAM — 6 pillars/boxes connected visually]",
    "Priority 1: Market Expansion",
    "Priority 2: Operational Excellence",
    "Priority 3: Digital Transformation",
    "Priority 4: Talent & Culture",
    "Priority 5: Sustainability",
    "Priority 6: Financial Resilience",
])

# Slide 4: Financial Performance
add_slide(doc, "Financial Performance Snapshot", [
    "[ADD FINANCIAL TREND CHART]",
    "Revenue targets vs. actuals to be shown",
    "Key metrics: Revenue, EBITDA, Free Cash Flow",
    "[EXPAND WITH ACTUAL DATA FROM FINANCIALS]",
])

# Slide 5: Year Ahead
add_slide(doc, "Looking Ahead: FY2024 Priorities", [
    "[EXPAND — THIS IS ONLY SLIDE 5 OF 12 REQUIRED]",
    "Capital allocation priorities",
    "Key initiatives by quarter",
    "Risk factors and mitigations",
    "[ADD REMAINING SLIDES: Risk, Initiatives, Milestones, etc.]",
])

doc.save("/home/ga/Documents/Presentations/board_strategy_2024.odp")
print("5-slide board strategy stub created")
PYEOF

sudo chown -R ga:ga /home/ga/Documents/Presentations/

# Record baseline
echo "5" > /tmp/board_initial_slides
date +%s > /tmp/task_start_timestamp

su - ga -c "DISPLAY=:1 scrot /tmp/task_start_screenshot.png" || true

# Launch LibreOffice Impress
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/board_strategy_2024.odp > /tmp/impress_board.log 2>&1 &"

wait_for_process "soffice" 20
wait_for_window "LibreOffice Impress" 90

sleep 2
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Board Strategy Review Task Setup Complete ==="
echo "Data: /home/ga/Documents/Presentations/world_economic_data.csv (IMF WEO 2023)"
echo "Draft: /home/ga/Documents/Presentations/board_strategy_2024.odp (5 slides)"
echo "Goal: 12-slide board strategy deck, 3+ charts, strategy diagram 6+ shapes,"
echo "      notes on ALL 12+ slides, also export PPTX"
