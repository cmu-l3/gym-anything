#!/bin/bash
echo "=== Setting up clinical_module_fix task ==="

source /workspace/scripts/task_utils.sh

kill_wps

pip3 install python-pptx lxml 2>/dev/null || true

# Remove any previous output file
rm -f /home/ga/Documents/ACLS_corrected.pptx

# Record task start timestamp AFTER cleaning output files
date +%s > /tmp/clinical_module_fix_start_ts

# Create ACLS lecture deck with 22 slides
# Real data sources:
#   - AHA ACLS 2020 Guidelines: Circulation. 2020;142(suppl 2):S366-S468
#   - BLS adult compression rate 100-120/min; depth 2-2.4 inches
#   - Adult epinephrine: 1 mg IV/IO every 3-5 min (not weight-based)
#   - VF/pVT: shock first, CPR 2 min, epinephrine after 2nd shock
#   - Asystole/PEA: epinephrine ASAP, no shock indicated
#   - Amiodarone: 300 mg IV/IO for VF/pVT (first dose)
#   - Lidocaine: 1-1.5 mg/kg IV/IO (alternative to amiodarone)
#   - Post-cardiac arrest target SBP >90 mmHg, SpO2 94-99%, PaCO2 35-45
# PALS contaminating data (pediatric-specific content):
#   - Pediatric epinephrine: 0.01 mg/kg IV/IO (weight-based)
#   - Pediatric compression depth: at least 1/3 AP diameter
#   - Pediatric shockable rhythm dose: 2 J/kg, then 4 J/kg
python3 << 'PYEOF'
import os
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor

PPTX_PATH = '/home/ga/Documents/ACLS_lecture.pptx'
os.makedirs('/home/ga/Documents', exist_ok=True)

prs = Presentation()
prs.slide_width  = Emu(9144000)
prs.slide_height = Emu(6858000)

def get_layout(prs):
    for layout in prs.slide_layouts:
        phs = {ph.placeholder_format.idx for ph in layout.placeholders}
        if 0 in phs and 1 in phs:
            return layout
    return prs.slide_layouts[1]

def add_slide(prs, title_text, body_lines):
    layout = get_layout(prs)
    slide = prs.slides.add_slide(layout)
    for ph in slide.placeholders:
        if ph.placeholder_format.idx == 0:
            ph.text = title_text
        elif ph.placeholder_format.idx == 1:
            tf = ph.text_frame
            tf.clear()
            for i, line in enumerate(body_lines):
                if i == 0:
                    tf.paragraphs[0].text = line
                else:
                    p = tf.add_paragraph()
                    p.text = line
    return slide

# NOTE: Contaminating PALS slides at positions 5, 12, 19 (1-indexed)
# All other slides are valid adult ACLS content

slides_data = [
    # Slide 1
    ("Adult ACLS Course: Module 1 — Core Algorithms",
     ["American Heart Association Advanced Cardiovascular Life Support",
      "2020 AHA Guidelines (Circulation 2020;142(suppl 2):S366-S468)",
      "Faculty: Emergency Medicine Department",
      "Target audience: Advanced practice providers and physicians",
      "CME Credit: 4.0 AMA PRA Category 1 Credits™"]),

    # Slide 2
    ("Adult BLS Review: Foundation for ACLS",
     ["Compression rate: 100–120 compressions per minute",
      "Compression depth: At least 2 inches (5 cm), not exceeding 2.4 inches",
      "Full chest recoil between compressions",
      "Minimize interruptions: pre-shock pause <10 seconds",
      "CPR ratio: 30:2 (before advanced airway); continuous with advanced airway"]),

    # Slide 3
    ("Cardiac Arrest Recognition and Activation",
     ["Unresponsive, not breathing or only gasping: activate emergency response",
      "Check pulse: no more than 10 seconds (carotid in adults)",
      "If no definite pulse: begin high-quality CPR immediately",
      "Attach AED/defibrillator as soon as available",
      "Minimize pre-shock CPR interruption to <10 seconds"]),

    # Slide 4
    ("VF/Pulseless VT Algorithm — Overview",
     ["Shockable rhythm: initiate shock sequence",
      "Deliver shock → immediately resume CPR × 2 minutes",
      "After 2nd shock: administer vasopressor (epinephrine 1 mg IV/IO)",
      "After 3rd shock (if persistent VF/pVT): amiodarone 300 mg IV/IO",
      "Continue CPR loops; reassess rhythm every 2 minutes"]),

    # Slide 5 — CONTAMINATING PALS SLIDE (must be removed)
    ("PALS Overview: Pediatric BLS Differences",
     ["Pediatric BLS differs from adult BLS in key respects",
      "Compression depth: at least 1/3 AP diameter (approx. 1.5 in infant, 2 in child)",
      "Compression rate: 100–120/min (same as adult)",
      "Ratio: 30:2 (single rescuer); 15:2 (two rescuers for healthcare providers)",
      "IMPORTANT: These are PALS guidelines — NOT applicable to adult ACLS module"]),

    # Slide 6
    ("Adult Pharmacology: Epinephrine in Cardiac Arrest",
     ["Epinephrine dose: 1 mg IV/IO every 3–5 minutes (FIXED dose, not weight-based)",
      "For VF/pVT: give after second unsuccessful shock",
      "For asystole/PEA: give as soon as IV/IO access established",
      "Epinephrine increases coronary and cerebral perfusion pressure",
      "Evidence: PARAMEDIC2 trial (NEJM 2018;379:711-21): improved 30-day survival"]),

    # Slide 7
    ("Adult Pharmacology: Amiodarone and Lidocaine",
     ["Amiodarone (1st line for shock-refractory VF/pVT):",
      "  First dose: 300 mg IV/IO bolus",
      "  Second dose: 150 mg IV/IO (if needed)",
      "Lidocaine (alternative if amiodarone unavailable):",
      "  First dose: 1–1.5 mg/kg IV/IO",
      "  Second dose: 0.5–0.75 mg/kg (max 3 doses or 3 mg/kg)"]),

    # Slide 8
    ("VF/Pulseless VT Algorithm — Full Sequence",
     ["1. CPR 2 min + O2 + attach monitor/defibrillator",
      "2. Shockable? YES → Shock → CPR 2 min → Check rhythm",
      "3. Still shockable? → Shock → CPR 2 min → Epinephrine 1 mg q3-5min",
      "4. Still shockable? → Shock → CPR 2 min → Amiodarone 300 mg",
      "5. Continue CPR loops; treat reversible causes (5 Hs, 5 Ts)"]),

    # Slide 9
    ("Asystole/PEA Algorithm",
     ["Non-shockable rhythm: CPR → Epinephrine ASAP",
      "No shock for asystole or PEA (no organized electrical activity to cardiovert)",
      "Epinephrine 1 mg IV/IO every 3–5 minutes",
      "Search for and treat reversible causes",
      "5 Hs: Hypovolemia, Hypoxia, H+ (acidosis), Hypo/hyperkalemia, Hypothermia"]),

    # Slide 10
    ("Reversible Causes: The 5 Hs and 5 Ts",
     ["5 Hs: Hypovolemia | Hypoxia | H+ acidosis | Hypo/hyperkalemia | Hypothermia",
      "5 Ts: Tension pneumothorax | Tamponade (cardiac) | Toxins | Thrombosis (pulmonary) | Thrombosis (coronary)",
      "Systematic search improves ROSC rates",
      "Point-of-care ultrasound (POCUS) aids in identifying tamponade, pneumothorax, PE",
      "Consider empirical treatment if cause is suspected but unconfirmed"]),

    # Slide 11
    ("Advanced Airway Management in Cardiac Arrest",
     ["Bag-valve-mask (BVM) acceptable as initial airway (equal outcomes to ETI in out-of-hospital arrest)",
      "Supraglottic airway (LMA, King LT) or endotracheal intubation when indicated",
      "Target SpO2 94%–99% post-ROSC (avoid hyperoxia)",
      "After advanced airway: continuous compressions at 100–120/min",
      "Ventilation rate: 10 breaths/min (1 breath every 6 seconds)"]),

    # Slide 12 — CONTAMINATING PALS SLIDE (must be removed)
    ("Pediatric Drug Dosing: Weight-Based Epinephrine",
     ["PALS epinephrine dose: 0.01 mg/kg IV/IO (weight-based — NOT a fixed dose)",
      "Maximum single dose: 1 mg",
      "Use Broselow tape or length-based resuscitation tool for weight estimation",
      "Repeat every 3–5 minutes",
      "IMPORTANT: This slide belongs to PALS, not the adult ACLS module"]),

    # Slide 13
    ("Post-Cardiac Arrest Care: Hemodynamic Targets",
     ["Target systolic BP ≥90 mmHg (or MAP ≥65 mmHg)",
      "IV fluid bolus 1–2 L if SBP <90 mmHg",
      "Vasopressor: norepinephrine or epinephrine infusion if hypotensive",
      "12-lead ECG: perform immediately to identify STEMI",
      "Emergent coronary angiography for suspected coronary cause"]),

    # Slide 14
    ("Post-Cardiac Arrest Care: Oxygenation and Ventilation",
     ["Target SpO2 94%–99% (titrate FiO2 to lowest level achieving target)",
      "Avoid hyperoxia: associated with worse neurological outcomes",
      "Target PaCO2 35–45 mmHg (normocapnia)",
      "Avoid hyperventilation: causes cerebral vasoconstriction",
      "Continuous SpO2 and end-tidal CO2 (ETCO2) monitoring"]),

    # Slide 15
    ("Targeted Temperature Management (TTM)",
     ["TTM recommended for comatose adult ACLS survivors",
      "Target temperature: 32–36°C for 24 hours (TTM2 Trial, NEJM 2021;384:2138-2149)",
      "Avoid fever (T >37.7°C) for at least 72 hours post-arrest",
      "IV saline for surface or endovascular cooling",
      "Rewarming: at a rate of 0.25–0.5°C per hour to normothermia"]),

    # Slide 16
    ("Bradycardia Algorithm — Adult",
     ["Unstable bradycardia (HR <50 bpm with symptoms): act immediately",
      "Symptoms: hypotension, AMS, chest pain, acute heart failure, shock",
      "First-line: Atropine 0.5 mg IV bolus (repeat q3-5min, max 3 mg)",
      "If atropine ineffective: transcutaneous pacing (preferred) or dopamine/epinephrine infusion",
      "Consider cardiology consult for persistent high-degree AV block"]),

    # Slide 17
    ("Tachycardia Algorithm — Adult: Stable vs. Unstable",
     ["Unstable (hypotension, AMS, chest pain, shock): immediate synchronized cardioversion",
      "Stable: assess QRS width and rhythm regularity",
      "Regular narrow QRS: vagal maneuvers → adenosine 6 mg IV rapid push",
      "Regular wide QRS: adenosine (if regular, monomorphic); consider antiarrhythmics",
      "Irregular AF with RVR: rate control with beta-blocker or calcium channel blocker"]),

    # Slide 18
    ("ACLS Special Circumstances: Pregnancy",
     ["Perform CPR with left lateral tilt (15–30°) or manual uterine displacement",
      "Perimortem cesarean delivery (PMCD) if no ROSC within 4 minutes",
     "PMCD target: within 5 minutes of cardiac arrest (4-minute rule)",
      "All standard ACLS drugs and defibrillation energy doses remain the same",
      "Call obstetric team immediately upon cardiac arrest in pregnancy"]),

    # Slide 19 — CONTAMINATING PALS SLIDE (must be removed)
    ("PALS Algorithms: Pediatric Shockable Rhythms",
     ["Initial shock for pediatric VF/pVT: 2 J/kg",
      "Subsequent shocks: 4 J/kg (and 4 J/kg for all subsequent shocks)",
      "Pediatric epinephrine for VF/pVT: 0.01 mg/kg IV/IO after 2nd shock",
      "Pediatric amiodarone: 5 mg/kg IV/IO",
      "IMPORTANT: These are PALS doses, not adult ACLS doses"]),

    # Slide 20
    ("ACLS Special Circumstances: Opioid Overdose",
     ["Opioid-associated life-threatening emergency: activate emergency response",
      "Support ventilation: BVM at 1 breath/5-6 sec if pulse present",
      "Naloxone: 0.4–2 mg IV/IO/IM/IN; repeat every 2–3 min as needed",
      "If no pulse: begin CPR immediately; standard ACLS algorithm",
      "Observe minimum 4 hours after naloxone administration"]),

    # Slide 21
    ("Airway Management: BVM and Intubation Tips",
     ["Two-person BVM: one masks, one compresses bag — reduces fatigue",
      "Sellick maneuver (cricoid pressure): not routinely recommended (AHA 2020)",
      "RSI pre-oxygenation: 3 minutes of 100% FiO2 or 8 vital capacity breaths",
      "Confirm ETI: waveform capnography (most reliable); secondary: chest rise, auscultation",
      "ETCO2 >10 mmHg during CPR suggests adequate cardiac output and predicts ROSC"]),

    # Slide 22
    ("ACLS Module 1 Summary and Learning Objectives",
     ["LO 1: Apply the VF/pVT algorithm with correct drug doses and timing",
      "LO 2: Apply the asystole/PEA algorithm",
      "LO 3: Differentiate unstable bradycardia from unstable tachycardia",
      "LO 4: Describe post-cardiac arrest care targets (hemodynamics, TTM, oxygenation)",
      "LO 5: Identify and manage ACLS special circumstances (pregnancy, opioid OD)"]),
]

for title_text, body_lines in slides_data:
    add_slide(prs, title_text, body_lines)

prs.save(PPTX_PATH)
print(f"Created {PPTX_PATH} with {len(prs.slides)} slides")
PYEOF

# Create the course review memo (does NOT name slide positions)
cat > /home/ga/Desktop/acls_review_memo.txt << 'DOCEOF'
EMERGENCY MEDICINE DEPARTMENT
CONTINUING MEDICAL EDUCATION PROGRAM

COURSE CONTENT REVIEW MEMO
To: ACLS Module 1 Course Director
From: CME Accreditation Office
Date: March 8, 2024
Re: AHA Program Faculty Agreement Violation — Urgent Correction Required

The uploaded ACLS Module 1 lecture deck at /home/ga/Documents/ACLS_lecture.pptx has been
flagged by the CME content review system. The following issue must be corrected
before the faculty review deadline.

ISSUE IDENTIFIED: PALS CONTENT CONTAMINATION

The ACLS adult lecture deck contains slides from the Pediatric Advanced Life Support
(PALS) curriculum. PALS and ACLS are distinct AHA programs with incompatible protocols.
Presenting pediatric-specific dosing (weight-based epinephrine), pediatric compression
depths, and pediatric defibrillation energy levels in an adult ACLS course context
violates the AHA Program Faculty Agreement and risks patient safety if the material
is used without clarification.

Specifically, any slide whose content describes pediatric-specific protocols — including
weight-based drug dosing, pediatric BLS deviations from adult standards, or pediatric
shockable rhythm dosing — must be removed. These slides are identifiable because:
  1. Their title or body explicitly references "PALS," "Pediatric," or "weight-based"
     dosing in a context inconsistent with adult ACLS.
  2. Their drug doses are weight-based (e.g., mg/kg) rather than the fixed adult doses
     specified in AHA ACLS 2020 Guidelines.

REQUIRED ACTION:

Remove ALL slides containing pediatric-specific content from the deck. Save the
corrected, adult-only ACLS lecture as:

    /home/ga/Documents/ACLS_corrected.pptx

Do NOT modify the original file at /home/ga/Documents/ACLS_lecture.pptx.

The corrected deck must contain ONLY slides appropriate for the Adult ACLS curriculum
as described in: Circulation. 2020;142(suppl 2):S366–S468.

If you have questions, contact the CME Accreditation Office at cme@medschool.edu.
DOCEOF

chown ga:ga /home/ga/Documents/ACLS_lecture.pptx
chown ga:ga /home/ga/Desktop/acls_review_memo.txt
chown -R ga:ga /home/ga/Documents

launch_wps_with_file "/home/ga/Documents/ACLS_lecture.pptx"

elapsed=0
while [ $elapsed -lt 60 ]; do
    dismiss_eula_if_present
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "ACLS_lecture"; then
        echo "WPS loaded ACLS_lecture.pptx after ${elapsed}s"
        sleep 3
        break
    fi
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "WPS Office"; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1280 630 click 1 2>/dev/null || true
        sleep 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

maximize_wps
sleep 2
take_screenshot /tmp/clinical_module_fix_start_screenshot.png

echo "=== clinical_module_fix setup complete ==="
echo "ACLS_lecture.pptx created and ready for review"
echo "Review memo placed on Desktop"
