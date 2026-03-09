#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Executive Board Report Task ==="

sudo -u ga mkdir -p /home/ga/Documents

# Create raw departmental data document
# Based on typical mid-market industrial company quarterly reporting patterns
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Raw email dumps from department heads - no structure
doc.add_paragraph("Q3 2024 Department Updates - Vertex Dynamics Corp")
doc.add_paragraph("Compiled from department head email submissions")
doc.add_paragraph("Board meeting: October 28, 2024")
doc.add_paragraph("")

doc.add_paragraph("From: James Rodriguez, CFO")
doc.add_paragraph("Subject: Q3 Financial Summary")
doc.add_paragraph(
    "Quick update on Q3 numbers before the board deck is due. Revenue came in at "
    "$48.2 million which is $3.2M or 7.1% above the $45.0M budget, primarily driven "
    "by the defense contracts we closed in August. Year-over-year we're up 12% from "
    "Q3 2023's $43.0M. Cost of goods sold was $31.3M giving us a gross margin of "
    "35.1% which is slightly below our 36% target but we had those material cost "
    "increases I flagged in July. Operating expenses came in at $12.8M - that's $0.3M "
    "over budget due to the consulting fees for the ERP migration. Net income after "
    "tax was $4.1M versus $3.8M budget. Cash position is strong at $22.5M, up from "
    "$19.8M at end of Q2. AR days improved to 42 from 48. Capex was $3.2M against "
    "$4.0M budget - we deferred the CNC machine purchase to Q4. One concern: our "
    "debt-to-equity ratio crept up to 0.82 from 0.75 due to the $5M term loan for "
    "the Building C expansion."
)
doc.add_paragraph("")

doc.add_paragraph("From: Patricia Kowalski, VP Operations")
doc.add_paragraph("Subject: Operations Q3 Report")
doc.add_paragraph(
    "Q3 was strong for operations overall. Overall Equipment Effectiveness (OEE) "
    "hit 87.3% against our 85% target - best quarter this year. Production output "
    "was 12,400 units versus 11,500 planned, a 7.8% beat. On-time delivery rate was "
    "94.2% which is above our 93% target. Scrap rate improved to 2.1% from 2.8% in "
    "Q2 thanks to the Six Sigma project on Line 3. Safety: we had 2 recordable "
    "incidents this quarter versus 4 in Q2, giving us a TRIR of 1.8 against our "
    "2.0 target. Inventory turns were 6.2x against 6.5x target - we're carrying "
    "extra raw materials as a hedge against the shipping disruptions. Headcount is "
    "at 485 versus 480 authorized, we brought on 5 temp workers for the defense "
    "contract surge. Employee turnover was 8.2% annualized, down from 11% last year. "
    "Biggest risk: the Building C HVAC system needs replacement sooner than planned, "
    "estimating $800K cost in Q1 2025."
)
doc.add_paragraph("")

doc.add_paragraph("From: Michael Torres, VP Sales & Marketing")
doc.add_paragraph("Subject: Sales update Q3")
doc.add_paragraph(
    "New bookings for Q3 were $52.1M which puts our book-to-bill ratio at 1.08 - "
    "healthy pipeline. Backlog stands at $78.4M, that's about 5 months of revenue. "
    "Won 3 new customers this quarter: Northrop Grumman ($4.2M/year), Caterpillar "
    "($2.8M/year), and Emerson Electric ($1.5M/year). Lost one customer - Honeywell "
    "consolidated to a single supplier and we weren't selected ($3.1M/year impact "
    "starting Q1 2025). Customer satisfaction score was 8.4/10, up from 8.1. "
    "Marketing generated 145 qualified leads this quarter versus 120 target. Website "
    "traffic up 23% after the trade show in September. Sales headcount is 32 versus "
    "30 budgeted - we hired two territory managers for the Southeast expansion. "
    "Biggest opportunity: the DoD is expanding the JLTV program and we're on the "
    "approved supplier list for precision machined components. Could be $15-20M/year "
    "starting mid-2025."
)
doc.add_paragraph("")

doc.add_paragraph("From: Dr. Anika Sharma, VP Engineering & R&D")
doc.add_paragraph("Subject: Engineering/R&D Q3")
doc.add_paragraph(
    "R&D spending was $2.4M in Q3, which is 5.0% of revenue and in line with our "
    "5% target. We filed 3 patents this quarter bringing our portfolio to 47 active "
    "patents. The next-gen lightweight alloy project (Project Phoenix) completed "
    "Phase 2 testing - tensile strength exceeded targets by 15%. Expected to be "
    "production-ready by Q2 2025. The automated inspection system using computer "
    "vision is in pilot on Line 2 and showing 99.2% defect detection rate versus "
    "97% for manual inspection. Full deployment planned for Q1 2025, estimated "
    "savings of $1.2M/year from reduced QC labor and scrap. New product development "
    "pipeline has 8 projects, 3 of which are expected to generate revenue in 2025. "
    "We need to discuss hiring 2 additional metallurgical engineers - we're "
    "stretched thin with the Phoenix project and the 3 customer qualification "
    "programs running simultaneously."
)
doc.add_paragraph("")

doc.add_paragraph("From: Karen Mitchell, VP Human Resources")
doc.add_paragraph("Subject: HR metrics Q3")
doc.add_paragraph(
    "Total headcount at end of Q3 is 485 FTEs plus 12 contractors. We filled 23 "
    "positions this quarter with an average time-to-fill of 38 days (target: 35 days). "
    "Employee engagement survey results came back at 72% favorable, which is up from "
    "68% last year but still below our 75% target. Training hours per employee were "
    "8.5 this quarter versus 10 target - we fell behind due to the production surge. "
    "Benefits costs per employee were $14,200/quarter, up 6% from last year due to "
    "healthcare premium increases. We completed the compensation benchmarking study "
    "and found we're at 95th percentile for production roles but only 82nd percentile "
    "for engineering - this is contributing to the engineering retention challenge. "
    "DEI metrics: workforce is 34% female (up from 32%), 28% underrepresented "
    "minorities (same). Leadership pipeline: 4 high-potential employees completed "
    "the executive development program this quarter."
)
doc.add_paragraph("")

doc.add_paragraph("From: James Rodriguez, CFO")
doc.add_paragraph("Subject: Key risks and strategic items for board discussion")
doc.add_paragraph(
    "Items I want to flag for board discussion: 1) The Building C expansion is on "
    "track for Q2 2025 completion but costs have escalated 12% above original budget "
    "due to steel prices. Current estimate is $8.4M versus $7.5M approved. Need board "
    "approval for the additional $0.9M. 2) We should discuss the Honeywell customer "
    "loss and mitigation strategy - Mike Torres has a plan to backfill the revenue. "
    "3) The ERP migration to SAP S/4HANA is 60% complete, on track for Q1 2025 "
    "go-live but we may need to extend the implementation partner contract by 2 months "
    "($180K additional). 4) Given the strong DoD pipeline opportunity, should we "
    "accelerate the ITAR compliance program? Current timeline is Q3 2025, could be "
    "pulled to Q1 2025 for approximately $350K additional investment. 5) Succession "
    "planning: VP Operations Patricia Kowalski has indicated she plans to retire in "
    "18 months. We need to begin the search process."
)

doc.save("/home/ga/Documents/quarterly_raw.docx")
print("Created raw quarterly data document")
PYEOF

sudo chown ga:ga /home/ga/Documents/quarterly_raw.docx
sudo chmod 666 /home/ga/Documents/quarterly_raw.docx

date +%s > /tmp/executive_board_report_start_ts

echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORMTHEME=gtk2 wps /home/ga/Documents/quarterly_raw.docx > /tmp/wps_task.log 2>&1 &"

if ! wait_for_process "wps" 20; then
    echo "ERROR: WPS Writer failed to start"
fi

sleep 5

max_eula_attempts=10
eula_attempt=0
document_visible=false

while [ $eula_attempt -lt $max_eula_attempts ] && [ "$document_visible" = "false" ]; do
    eula_attempt=$((eula_attempt + 1))
    if wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        dismiss_wps_eula 3
        sleep 2
    fi
    dismiss_wps_dialogs
    sleep 1
    if wmctrl -l | grep -qi "quarterly_raw\|Writer" && ! wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        document_visible=true
    else
        sleep 2
    fi
done

if ! wait_for_window "WPS Writer\|quarterly_raw\|Writer" 20; then
    echo "Warning: WPS window not detected"
fi

sleep 5

wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 1
fi

check_document_open() {
    local win_list=$(wmctrl -l 2>/dev/null)
    if echo "$win_list" | grep -qi "quarterly_raw"; then return 0; fi
    if echo "$win_list" | grep -qi "\.docx"; then return 0; fi
    if echo "$win_list" | grep -i "Writer" | grep -qiv "WPS Office$"; then return 0; fi
    return 1
}

max_open_attempts=5
open_attempt=0
document_opened=false

while [ $open_attempt -lt $max_open_attempts ] && [ "$document_opened" = "false" ]; do
    open_attempt=$((open_attempt + 1))
    if check_document_open; then document_opened=true; break; fi
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/quarterly_raw.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
    if check_document_open; then document_opened=true; break; fi
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/quarterly_raw.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
done

sleep 3
DISPLAY=:1 xdotool key ctrl+Home
sleep 1

for i in 1 2 3; do
    DISPLAY=:1 wmctrl -c "System Check" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done

take_screenshot /tmp/executive_board_report_start_screenshot.png

echo "=== Executive Board Report Task Setup Complete ==="
