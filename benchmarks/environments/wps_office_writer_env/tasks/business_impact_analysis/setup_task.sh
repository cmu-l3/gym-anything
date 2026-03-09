#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Business Impact Analysis Task ==="

sudo -u ga mkdir -p /home/ga/Documents

# Create raw interview notes document - unstructured stakeholder data
# Based on ISO 22301 Business Continuity and FEMA BIA template patterns
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# All content is raw interview notes - no structure, no headings, no tables
doc.add_paragraph("Business Impact Analysis - Interview Notes")
doc.add_paragraph("Pinnacle Financial Group")
doc.add_paragraph("Interviews conducted: February 12-16, 2024")
doc.add_paragraph("Interviewer: J. Morrison, Business Continuity Manager")
doc.add_paragraph("")

doc.add_paragraph(
    "Interview with Sarah Chen, VP of Technology (Feb 12, 9:00 AM)"
)
doc.add_paragraph(
    "The Core Banking Platform is our most critical system. It handles all deposit, "
    "withdrawal, and account management transactions. If this goes down, we cannot "
    "process any customer transactions at all. Sarah estimated that we process about "
    "$45 million in transactions daily through this platform. The maximum acceptable "
    "downtime before severe financial impact is 4 hours - after that we start losing "
    "customers and face regulatory penalties. She said the recovery time objective "
    "should be set at 2 hours, and we absolutely cannot lose more than 15 minutes of "
    "transaction data, so the recovery point objective is 15 minutes. The system "
    "depends on the Oracle database cluster, the F5 load balancers, and the Cisco "
    "network infrastructure. The maximum tolerable period of disruption is 8 hours "
    "before we would face regulatory action from the OCC."
)
doc.add_paragraph("")

doc.add_paragraph(
    "Interview with Marcus Williams, Director of Payment Operations (Feb 12, 2:00 PM)"
)
doc.add_paragraph(
    "Payment Processing is absolutely critical - it handles wire transfers, ACH "
    "processing, and real-time payments through FedNow. Daily volume is around "
    "12,000 transactions worth approximately $120 million. If payment processing "
    "goes down, we face immediate regulatory scrutiny and potential fines from the "
    "Federal Reserve. Marcus said the RTO needs to be 1 hour maximum. The RPO is "
    "zero - we cannot lose any payment transaction data whatsoever. The MTPD is "
    "4 hours. This system depends on the Core Banking Platform, the SWIFT network "
    "connection, and the Federal Reserve FedLine connection. Marcus mentioned that "
    "during Hurricane Sandy in 2012, a competitor lost payment processing for 3 days "
    "and the regulatory fallout took 2 years to resolve."
)
doc.add_paragraph("")

doc.add_paragraph(
    "Interview with Lisa Park, Chief Digital Officer (Feb 13, 10:00 AM)"
)
doc.add_paragraph(
    "The Customer Portal serves about 180,000 active users for online banking and "
    "mobile banking. While customers can still visit branches if the portal is down, "
    "extended outages cause significant customer complaints and social media backlash. "
    "Lisa estimated the RTO at 8 hours and the RPO at 1 hour. The maximum tolerable "
    "period of disruption is 24 hours before we start seeing measurable customer "
    "attrition. The portal depends on the Core Banking Platform, the CDN provider "
    "(Cloudflare), and the authentication service (Okta). She also noted that the "
    "mobile app and web portal share the same backend, so if one goes down, both go "
    "down. Impact is moderate in terms of revenue but high in terms of reputation."
)
doc.add_paragraph("")

doc.add_paragraph(
    "Interview with Dr. Robert Nakamura, Head of Risk Management (Feb 14, 9:30 AM)"
)
doc.add_paragraph(
    "Risk Analytics runs our credit scoring models, fraud detection algorithms, and "
    "market risk calculations. If this system is offline, we cannot approve new loans "
    "or detect fraudulent transactions in real-time. During business hours, this is "
    "critical because fraud losses accumulate quickly - Robert estimated $50,000 per "
    "hour in potential fraud exposure when the system is down. The RTO is 4 hours "
    "and RPO is 30 minutes. MTPD is 12 hours. Dependencies include the Core Banking "
    "Platform data feeds, the SAS analytics server cluster, and the Bloomberg market "
    "data terminal. Robert stressed that the ML models need to be retrained if data "
    "loss exceeds 2 hours, which would extend recovery to 24+ hours."
)
doc.add_paragraph("")

doc.add_paragraph(
    "Interview with Jennifer Walsh, VP of Human Resources (Feb 14, 2:00 PM)"
)
doc.add_paragraph(
    "Email and Communications including Microsoft 365, Teams, and our internal "
    "messaging system. Jennifer acknowledged this isn't as time-critical as "
    "transaction systems, but pointed out that during a crisis event, communications "
    "are essential for coordinating the response. The RTO is 12 hours for normal "
    "operations but should be 2 hours during an active incident. RPO is 4 hours - "
    "losing a few hours of email is acceptable. MTPD is 48 hours. This depends on "
    "Microsoft 365 cloud services and our on-premise Exchange server for archive. "
    "Jennifer noted that during a 2023 Teams outage, several important client meetings "
    "had to be rescheduled, causing moderate reputational damage."
)
doc.add_paragraph("")

doc.add_paragraph(
    "Interview with David Okonkwo, Chief Compliance Officer (Feb 15, 11:00 AM)"
)
doc.add_paragraph(
    "Regulatory Reporting covers our daily CCAR submissions, quarterly Call Reports "
    "to the FDIC, and annual stress testing under Dodd-Frank. David emphasized that "
    "missing a regulatory filing deadline results in automatic penalties starting at "
    "$10,000 per day and escalating. The system has some flexibility because most "
    "reports have multi-day deadlines, so the RTO is 24 hours. RPO is 8 hours "
    "because we can regenerate reports from source data. MTPD is 72 hours, but only "
    "if no filing deadlines fall within that window. Dependencies are the Core Banking "
    "Platform for source data, the Axiom regulatory reporting tool, and the secure "
    "FTP connection to the Federal Reserve and FDIC. David said the biggest risk is "
    "actually data integrity rather than system availability - if the source data is "
    "corrupted, the reports will be wrong and we may not know for weeks."
)
doc.add_paragraph("")

doc.add_paragraph(
    "Additional notes from J. Morrison:"
)
doc.add_paragraph(
    "Overall risk assessment observations: The most likely disruption scenarios are "
    "ransomware attack (estimated probability: high, based on 3 incidents in the "
    "financial sector this quarter), power outage at primary data center (probability: "
    "medium, last occurred 18 months ago), and ISP failure (probability: medium-low). "
    "The highest impact scenarios are ransomware (critical impact - could take down "
    "all systems simultaneously), fire or flood at HQ (high impact - would require "
    "full DR activation), and pandemic/workforce unavailability (medium impact - "
    "proven manageable after COVID). Single points of failure identified: the Oracle "
    "DBA team (only 2 people), the SWIFT connection (single vendor), and the primary "
    "data center cooling system (failed once in 2022)."
)
doc.add_paragraph("")
doc.add_paragraph(
    "Responsibility notes: IT Operations (Tom Bradley) owns the technical recovery "
    "for Core Banking, Payment Processing, and Risk Analytics. The Digital team "
    "(Lisa Park) owns Customer Portal recovery. IT Support (Amy Rodriguez) handles "
    "Email and Communications recovery. Compliance (David Okonkwo) owns Regulatory "
    "Reporting recovery but needs IT Operations support for data restoration. The "
    "Crisis Management Team is responsible for overall coordination and consists of "
    "the CTO, COO, CCO, and CISO. External vendors involved: Oracle (database support), "
    "IBM (DR site), Microsoft (365 services), and Cloudflare (CDN)."
)

doc.save("/home/ga/Documents/bia_notes.docx")
print("Created raw BIA interview notes document")
PYEOF

sudo chown ga:ga /home/ga/Documents/bia_notes.docx
sudo chmod 666 /home/ga/Documents/bia_notes.docx

date +%s > /tmp/business_impact_analysis_start_ts

echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORMTHEME=gtk2 wps /home/ga/Documents/bia_notes.docx > /tmp/wps_task.log 2>&1 &"

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
    if wmctrl -l | grep -qi "bia_notes\|Writer" && ! wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        document_visible=true
    else
        sleep 2
    fi
done

if ! wait_for_window "WPS Writer\|bia_notes\|Writer" 20; then
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
    if echo "$win_list" | grep -qi "bia_notes"; then return 0; fi
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
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/bia_notes.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
    if check_document_open; then document_opened=true; break; fi
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/bia_notes.docx" &
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

take_screenshot /tmp/business_impact_analysis_start_screenshot.png

echo "=== Business Impact Analysis Task Setup Complete ==="
