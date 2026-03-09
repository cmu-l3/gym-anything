#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Regulatory Submission Format Task ==="

sudo -u ga mkdir -p /home/ga/Documents

# Create the raw PBRER document - all content as unformatted plain text
# Based on ICH E2C(R2) guideline structure for Periodic Benefit-Risk Evaluation Reports
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Everything is plain text, no headings, no formatting, no tables
# The agent must discover the structure and apply formatting

doc.add_paragraph(
    "PERIODIC BENEFIT-RISK EVALUATION REPORT"
)
doc.add_paragraph(
    "Drug Name: Nexovant (casirivimab/imdevimab)"
)
doc.add_paragraph(
    "Report Number: PBRER-2024-NXV-003"
)
doc.add_paragraph(
    "International Birth Date: 15 March 2021"
)
doc.add_paragraph(
    "Reporting Interval: 01 April 2023 to 31 March 2024"
)
doc.add_paragraph(
    "Date of Report: 15 June 2024"
)
doc.add_paragraph(
    "Marketing Authorization Holder: Meridian Pharmaceuticals, Inc."
)
doc.add_paragraph("")

doc.add_paragraph(
    "Executive Summary"
)
doc.add_paragraph(
    "This Periodic Benefit-Risk Evaluation Report covers the reporting interval from "
    "01 April 2023 to 31 March 2024 for Nexovant (casirivimab/imdevimab), a monoclonal "
    "antibody combination product indicated for the treatment of moderate-to-severe "
    "rheumatoid arthritis in adults who have had an inadequate response to one or more "
    "disease-modifying antirheumatic drugs (DMARDs). During the reporting period, "
    "approximately 245,000 patients were exposed worldwide. The overall benefit-risk "
    "profile of Nexovant remains favorable. Two new signals were evaluated during "
    "this interval: hepatotoxicity (confirmed signal, label updated) and interstitial "
    "lung disease (refuted, insufficient evidence). No changes to the indication, "
    "dosing, or contraindications are recommended at this time."
)

doc.add_paragraph("")
doc.add_paragraph(
    "Introduction"
)
doc.add_paragraph(
    "Nexovant (casirivimab/imdevimab) is a combination of two fully human monoclonal "
    "antibodies that bind to distinct epitopes on the interleukin-6 receptor (IL-6R). "
    "It was first approved by the FDA on 15 March 2021 under NDA 214518 for the "
    "treatment of moderate-to-severe rheumatoid arthritis. The approved dosage is "
    "200 mg subcutaneous injection every two weeks or 400 mg every four weeks. "
    "This report is prepared in accordance with ICH E2C(R2) guidelines and covers "
    "safety data accumulated during the reporting interval."
)

doc.add_paragraph("")
doc.add_paragraph(
    "Worldwide Marketing Authorization Status"
)
doc.add_paragraph(
    "Nexovant is currently approved in 47 countries. United States: approved 15 March "
    "2021 for moderate-to-severe rheumatoid arthritis. European Union: approved 22 June "
    "2021 via centralized procedure for the same indication. Japan: approved 10 September "
    "2021. Canada: approved 05 January 2022. Australia: approved 18 March 2022. "
    "Additional approvals have been granted in South Korea, Brazil, Mexico, and 39 other "
    "countries. No marketing authorization has been withdrawn, suspended, or revoked "
    "during the reporting period."
)

doc.add_paragraph("")
doc.add_paragraph(
    "Changes to Reference Safety Information"
)
doc.add_paragraph(
    "During the reporting interval, the following changes were made to the Reference "
    "Safety Information (Company Core Data Sheet, CCDS): Section 4.4 Special Warnings "
    "and Precautions was updated to include hepatotoxicity monitoring recommendations "
    "based on the confirmed safety signal. Section 4.8 Undesirable Effects was updated "
    "to include drug-induced liver injury (DILI) as an uncommon adverse reaction "
    "(frequency 1/1,000 to 1/100). No other changes were made to the CCDS."
)

doc.add_paragraph("")
doc.add_paragraph(
    "Patient Exposure"
)
doc.add_paragraph(
    "Estimated cumulative patient exposure since international birth date: 1,250,000 "
    "patients. Estimated patient exposure during the reporting interval: 245,000 patients. "
    "Patient exposure by region during reporting interval: North America 98,000 patients, "
    "Europe 82,000 patients, Asia-Pacific 45,000 patients, Rest of World 20,000 patients. "
    "Clinical trial exposure during reporting interval: 3,200 patients across 4 ongoing "
    "clinical trials (Study NXV-301, NXV-302, NXV-401, NXV-501)."
)

doc.add_paragraph("")
doc.add_paragraph(
    "Actions Taken in the Reporting Interval for Safety Reasons"
)
doc.add_paragraph(
    "The following regulatory actions were taken during the reporting interval: "
    "FDA required label update for hepatotoxicity warning (effective 15 November 2023). "
    "EMA PRAC recommended addition of hepatotoxicity to SmPC Section 4.4 (adopted "
    "15 January 2024). Health Canada issued Dear Healthcare Professional Communication "
    "regarding liver monitoring (20 December 2023). No product recalls, market "
    "withdrawals, or clinical trial suspensions occurred during the reporting period."
)

doc.add_paragraph("")
doc.add_paragraph(
    "Signal Evaluation"
)
doc.add_paragraph(
    "Signal 1 - Hepatotoxicity: This signal was initially detected through "
    "disproportionality analysis of the global safety database in June 2023 "
    "(PRR = 2.8, IC025 = 1.4). A comprehensive review of 156 cases of hepatic "
    "events was conducted. Of these, 42 cases met the criteria for drug-induced "
    "liver injury (DILI) per the RUCAM scale. The median time to onset was 12 weeks "
    "(range 3-48 weeks). Outcomes: 38 patients recovered after drug discontinuation, "
    "3 patients had ongoing liver function abnormalities at last follow-up, and "
    "1 patient required liver transplantation. This signal was confirmed. "
    "Risk minimization measures include liver function monitoring at baseline, "
    "monthly for the first 6 months, and every 3 months thereafter."
)
doc.add_paragraph(
    "Signal 2 - Interstitial Lung Disease (ILD): This signal was identified from "
    "a cluster of 8 spontaneous reports of interstitial lung disease received between "
    "August and December 2023. Upon detailed case review, 3 cases had confounding "
    "factors (pre-existing lung disease, concurrent methotrexate), 2 cases had "
    "insufficient information for causality assessment, and 3 cases were assessed "
    "as possible. Given the low reporting rate (0.003%), confounding factors, and "
    "absence of a plausible biological mechanism, this signal was refuted. Monitoring "
    "will continue."
)

doc.add_paragraph("")
doc.add_paragraph(
    "Summary of Adverse Reactions from Clinical Trials and Postmarketing"
)
doc.add_paragraph(
    "Adverse reactions reported during the reporting interval from all sources. "
    "Very common (>=10%): injection site reactions reported in 28.5% of patients, "
    "upper respiratory tract infections in 15.2% of patients, headache in 12.1% of "
    "patients. Common (>=1% to <10%): nasopharyngitis 8.4%, nausea 6.2%, fatigue 5.1%, "
    "elevated liver enzymes (ALT/AST) 4.8%, arthralgia 3.9%, hypertension 2.7%, "
    "rash 2.3%, urinary tract infection 1.8%. Uncommon (>=0.1% to <1%): drug-induced "
    "liver injury 0.4%, herpes zoster 0.3%, neutropenia 0.2%, anaphylaxis 0.15%. "
    "Rare (<0.1%): gastrointestinal perforation 0.05%, progressive multifocal "
    "leukoencephalopathy 0.01%."
)

doc.add_paragraph("")
doc.add_paragraph(
    "Integrated Benefit-Risk Analysis"
)
doc.add_paragraph(
    "Benefits: Nexovant has demonstrated sustained efficacy in reducing the signs and "
    "symptoms of rheumatoid arthritis, with ACR20 response rates of 67% at 24 weeks "
    "and 72% at 52 weeks in the pivotal Phase III trial (NXV-301). Radiographic "
    "progression was inhibited in 89% of patients at 52 weeks compared to 64% with "
    "placebo. Patient-reported outcomes including HAQ-DI, pain VAS, and SF-36 showed "
    "clinically meaningful improvements sustained through 104 weeks of treatment."
)
doc.add_paragraph(
    "Risks: The main identified risks include serious infections (incidence 3.2 per "
    "100 patient-years), hepatotoxicity (newly identified, estimated 0.4%), and "
    "injection site reactions (28.5%, generally mild). The hepatotoxicity signal "
    "represents a new important identified risk; however, the risk is manageable "
    "with appropriate monitoring as reflected in the updated labeling."
)
doc.add_paragraph(
    "Overall assessment: The benefit-risk balance of Nexovant remains favorable for "
    "the approved indication. The benefits of disease control in moderate-to-severe "
    "rheumatoid arthritis outweigh the identified and potential risks, provided that "
    "the risk minimization measures described in the product information are followed."
)

doc.add_paragraph("")
doc.add_paragraph(
    "Conclusion"
)
doc.add_paragraph(
    "Based on the comprehensive review of safety data during the reporting interval "
    "01 April 2023 to 31 March 2024, the benefit-risk profile of Nexovant remains "
    "favorable. The hepatotoxicity signal has been confirmed and appropriately "
    "addressed through label updates and risk minimization measures. The ILD signal "
    "has been refuted but will continue to be monitored. No new safety concerns have "
    "been identified that would alter the current benefit-risk assessment. "
    "The Marketing Authorization Holder recommends no changes to the approved "
    "indication, dosage, or contraindications at this time."
)

doc.save("/home/ga/Documents/pbrer_draft.docx")
print("Created raw PBRER document with no formatting")
PYEOF

sudo chown ga:ga /home/ga/Documents/pbrer_draft.docx
sudo chmod 666 /home/ga/Documents/pbrer_draft.docx

date +%s > /tmp/regulatory_submission_format_start_ts

echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORMTHEME=gtk2 wps /home/ga/Documents/pbrer_draft.docx > /tmp/wps_task.log 2>&1 &"

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
    if wmctrl -l | grep -qi "pbrer_draft\|Writer" && ! wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        document_visible=true
    else
        sleep 2
    fi
done

if ! wait_for_window "WPS Writer\|pbrer_draft\|Writer" 20; then
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
    if echo "$win_list" | grep -qi "pbrer_draft"; then return 0; fi
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
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/pbrer_draft.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
    if check_document_open; then document_opened=true; break; fi
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/pbrer_draft.docx" &
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

take_screenshot /tmp/regulatory_submission_format_start_screenshot.png

echo "=== Regulatory Submission Format Task Setup Complete ==="
