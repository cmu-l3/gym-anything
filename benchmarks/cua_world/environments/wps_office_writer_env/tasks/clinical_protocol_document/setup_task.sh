#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Clinical Protocol Document Task ==="

sudo -u ga mkdir -p /home/ga/Documents

# Create the poorly structured clinical protocol draft
# Based on IDSA/ASHP/SIDP Vancomycin Therapeutic Monitoring Guidelines (2020)
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# All content in Normal style - no headings, no tables, no structure
doc.add_paragraph("Vancomycin IV Administration Protocol")
doc.add_paragraph("St. Margaret's Medical Center")
doc.add_paragraph("Department of Pharmacy and Nursing")
doc.add_paragraph("Protocol Number: PHARM-ABX-2024-012")
doc.add_paragraph("Effective Date: January 1, 2024")
doc.add_paragraph("")

# No "Purpose" section - agent must add one

# No "Scope" section - agent must add one

# Indications section - no heading style
doc.add_paragraph("Indications for Vancomycin IV Therapy")
doc.add_paragraph(
    "Vancomycin is indicated for the treatment of serious infections caused by "
    "susceptible strains of methicillin-resistant Staphylococcus aureus (MRSA) and "
    "other gram-positive organisms. Specific indications include: complicated skin "
    "and soft tissue infections (cSSTI), bloodstream infections (bacteremia), "
    "infective endocarditis, bone and joint infections (osteomyelitis, septic "
    "arthritis), central nervous system infections (meningitis), and hospital-acquired "
    "pneumonia or ventilator-associated pneumonia caused by MRSA."
)

doc.add_paragraph("")

# Dosing section - all data in prose, should be in tables
doc.add_paragraph("Dosing Guidelines")
doc.add_paragraph(
    "Initial dosing for adults with normal renal function (CrCl > 90 mL/min): "
    "Loading dose of 25-30 mg/kg actual body weight (maximum 3,000 mg) infused over "
    "2 hours, followed by maintenance dosing of 15-20 mg/kg actual body weight every "
    "8-12 hours. For patients weighing greater than 120 kg, use adjusted body weight. "
    "For renal dose adjustments: CrCl 50-89 mL/min give 15-20 mg/kg every 12 hours, "
    "CrCl 30-49 mL/min give 15-20 mg/kg every 24 hours, CrCl 15-29 mL/min give "
    "15-20 mg/kg every 24-48 hours, CrCl less than 15 mL/min give 15-20 mg/kg and "
    "redose based on trough levels. For hemodialysis patients, give 15-20 mg/kg "
    "loading dose and redose 500-1000 mg after each dialysis session based on levels."
)
doc.add_paragraph(
    "Pediatric dosing: Neonates less than 1 week of age and less than 1200g give "
    "15 mg/kg every 24 hours. Neonates less than 1 week of age and greater than "
    "1200g give 15 mg/kg every 12 hours. Neonates 1-4 weeks of age give 15 mg/kg "
    "every 8 hours. Infants and children give 15 mg/kg every 6 hours (maximum "
    "60 mg/kg/day). Adolescents use adult dosing."
)

doc.add_paragraph("")

# Administration section - no heading
doc.add_paragraph("Administration and Infusion")
doc.add_paragraph(
    "Vancomycin must be administered by slow intravenous infusion only. Never "
    "administer by rapid IV push or bolus injection. Standard concentration: "
    "reconstitute each 500 mg vial with 10 mL Sterile Water for Injection, then "
    "further dilute in 100-250 mL of 0.9% Sodium Chloride or 5% Dextrose in Water. "
    "Maximum concentration: 5 mg/mL for peripheral IV, 10 mg/mL for central line. "
    "Infusion rate: administer over at least 60 minutes at a rate not exceeding "
    "10 mg/min. Doses greater than 1,000 mg should be infused over at least 90 "
    "minutes. Doses greater than 2,000 mg should be infused over at least 120 "
    "minutes to minimize the risk of Red Man Syndrome."
)

doc.add_paragraph("")

# Monitoring section - scattered data
doc.add_paragraph("Therapeutic Monitoring")
doc.add_paragraph(
    "Area Under the Curve (AUC)-guided monitoring is the preferred method per 2020 "
    "IDSA/ASHP/SIDP guidelines. Target AUC/MIC ratio of 400-600 mg*h/L assuming "
    "MIC of 1 mcg/mL. If AUC-guided monitoring is not available, trough-based "
    "monitoring may be used with target trough of 15-20 mcg/mL for serious "
    "infections. Obtain first trough level before the 4th dose (at steady state). "
    "Baseline monitoring before initiation: serum creatinine, BUN, CBC with "
    "differential, urinalysis. Ongoing monitoring: serum creatinine every 48-72 "
    "hours for stable patients, daily for critically ill patients or those on "
    "concurrent nephrotoxic agents. Vancomycin levels: obtain trough 30 minutes "
    "before the next dose. Recheck levels after dose adjustments (wait for new "
    "steady state, approximately 3-5 doses). Weekly CBC for therapy duration "
    "greater than 7 days to monitor for neutropenia."
)

doc.add_paragraph("")

# Adverse reactions in prose - should be a table
doc.add_paragraph("Adverse Reactions and Side Effects")
doc.add_paragraph(
    "Common adverse reactions (occurring in greater than 10% of patients): Red Man "
    "Syndrome or vancomycin infusion reaction characterized by flushing, erythema, "
    "and pruritus of the upper body, reported in approximately 25-30% of patients "
    "when infused too rapidly. Phlebitis at peripheral IV sites reported in 13% of "
    "patients. Less common adverse reactions (1-10%): nephrotoxicity manifesting as "
    "elevated serum creatinine, reported in 5-7% of patients with monotherapy and "
    "up to 33% with concurrent aminoglycosides. Drug fever occurring in approximately "
    "3% of patients. Nausea in 2% of patients. Uncommon adverse reactions (less than "
    "1%): ototoxicity (hearing loss or tinnitus) in 0.5% of patients, typically "
    "associated with supratherapeutic levels. Neutropenia in 0.3% of patients, "
    "usually reversible after discontinuation, more common with therapy exceeding "
    "14 days. Thrombocytopenia in 0.2% of patients. Linear IgA bullous dermatosis "
    "reported rarely. Stevens-Johnson Syndrome and toxic epidermal necrolysis "
    "reported in isolated case reports."
)

doc.add_paragraph("")

# Contraindications - no heading
doc.add_paragraph("Contraindications and Precautions")
doc.add_paragraph(
    "Absolute contraindications: known hypersensitivity or anaphylaxis to vancomycin "
    "or any component of the formulation. Relative contraindications and precautions: "
    "pre-existing hearing impairment (increased risk of ototoxicity), pre-existing "
    "renal impairment (dose adjustment required and increased monitoring), concurrent "
    "use of other nephrotoxic or ototoxic agents (aminoglycosides, amphotericin B, "
    "cisplatin, loop diuretics), pregnancy category C (use only if clearly needed "
    "and benefits outweigh risks), elderly patients over 65 years (increased risk "
    "of nephrotoxicity, consider lower initial doses)."
)

doc.add_paragraph("")

# No "Equipment Required" section - agent must add one

# References section - no heading
doc.add_paragraph("References")
doc.add_paragraph(
    "1. Rybak MJ, Le J, Lodise TP, et al. Therapeutic monitoring of vancomycin for "
    "serious methicillin-resistant Staphylococcus aureus infections: A revised "
    "consensus guideline and review by the American Society of Health-System "
    "Pharmacists, the Infectious Diseases Society of America, the Pediatric Infectious "
    "Diseases Society, and the Society of Infectious Diseases Pharmacists. Am J "
    "Health-Syst Pharm. 2020;77(11):835-864."
)
doc.add_paragraph(
    "2. Liu C, Bayer A, Cosgrove SE, et al. Clinical practice guidelines by the "
    "Infectious Diseases Society of America for the treatment of methicillin-resistant "
    "Staphylococcus aureus infections in adults and children. Clin Infect Dis. "
    "2011;52(3):e18-e55."
)
doc.add_paragraph(
    "3. Vancomycin [package insert]. Lake Forest, IL: Hospira, Inc.; 2021."
)

# No "Revision History" section - agent must add one

doc.save("/home/ga/Documents/vanc_protocol_draft.docx")
print("Created poorly structured vancomycin protocol draft")
PYEOF

sudo chown ga:ga /home/ga/Documents/vanc_protocol_draft.docx
sudo chmod 666 /home/ga/Documents/vanc_protocol_draft.docx

date +%s > /tmp/clinical_protocol_document_start_ts

echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORMTHEME=gtk2 wps /home/ga/Documents/vanc_protocol_draft.docx > /tmp/wps_task.log 2>&1 &"

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
    if wmctrl -l | grep -qi "vanc_protocol\|Writer" && ! wmctrl -l | grep -qi "License Agreement\|Kingsoft\|End User License\|EULA"; then
        document_visible=true
    else
        sleep 2
    fi
done

if ! wait_for_window "WPS Writer\|vanc_protocol\|Writer" 20; then
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
    if echo "$win_list" | grep -qi "vanc_protocol"; then return 0; fi
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
    su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/vanc_protocol_draft.docx" &
    sleep 5
    dismiss_wps_dialogs
    sleep 2
    if check_document_open; then document_opened=true; break; fi
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/vanc_protocol_draft.docx" &
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

take_screenshot /tmp/clinical_protocol_document_start_screenshot.png

echo "=== Clinical Protocol Document Task Setup Complete ==="
