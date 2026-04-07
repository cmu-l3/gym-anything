#!/bin/bash
set -euo pipefail

echo "=== Setting up Medical Grand Rounds Presentation Task ==="

source /workspace/scripts/task_utils.sh || true

# Clean up environment and kill any existing onlyoffice instances
pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true
sleep 1

# Setup Directories
MATERIALS_DIR="/home/ga/Documents/Presentations/Case_Materials"
sudo -u ga mkdir -p "$MATERIALS_DIR"

# 1. Create Clinical Narrative
cat > "$MATERIALS_DIR/clinical_narrative.txt" << 'EOF'
PATIENT DEMOGRAPHICS:
Age: 68 years
Sex: Female

CHIEF COMPLAINT:
Sudden onset crushing retrosternal chest pain and severe dyspnea.

HISTORY OF PRESENT ILLNESS:
The patient presented to the Emergency Department with acute, crushing chest pain radiating to the left arm, which began approximately 2 hours prior to arrival. The onset immediately followed a severe emotional stressor (unexpected loss of her spouse). 

HOSPITAL COURSE:
Initial ECG showed anterior ST-segment elevations. The patient was admitted to the CCU with suspicion of an acute anterior STEMI. Emergent coronary angiography was performed which revealed angiographically normal, clean coronary arteries with no obstructive lesions. Left ventriculography was performed demonstrating severe apical ballooning with basal hyperkinesis, classic for Takotsubo (stress) cardiomyopathy.

TREATMENT & OUTCOME:
Treated conservatively with beta-blockers, ACE inhibitors, and diuretics for transient heart failure. Follow-up echocardiogram at 4 weeks showed complete resolution of wall motion abnormalities and normalization of Left Ventricular Ejection Fraction (LVEF).
EOF

# 2. Create Cardiac Labs CSV
cat > "$MATERIALS_DIR/cardiac_labs.csv" << 'EOF'
Test_Name,Result,Units,Reference_Range,Flag
Troponin I,4.2,ng/mL,< 0.04,HIGH
NT-proBNP,4500,pg/mL,< 125,HIGH
CK-MB,15.4,ng/mL,< 5.0,HIGH
Creatinine,0.9,mg/dL,0.5 - 1.1,NORMAL
Potassium,4.1,mEq/L,3.5 - 5.0,NORMAL
EOF

# 3. Download Real Medical Images (Wikimedia Commons Public Domain/CC)
echo "Downloading medical images..."
# 12-lead ECG of Takotsubo
wget -q -O "$MATERIALS_DIR/ecg_admission.jpg" "https://upload.wikimedia.org/wikipedia/commons/e/e5/12_lead_ECG_of_Takotsubo_cardiomyopathy.jpg" || \
    convert -size 800x600 xc:white -fill black -gravity center -pointsize 48 -draw "text 0,0 'MOCK ECG IMAGE\nST ELEVATIONS'" "$MATERIALS_DIR/ecg_admission.jpg"

# Ventriculogram showing apical ballooning
wget -q -O "$MATERIALS_DIR/lv_angiogram.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/6/64/Takotsubo_ventriculogram_systole.png/800px-Takotsubo_ventriculogram_systole.png" || \
    convert -size 800x600 xc:black -fill white -gravity center -pointsize 48 -draw "text 0,0 'MOCK ANGIOGRAM\nAPICAL BALLOONING'" "$MATERIALS_DIR/lv_angiogram.jpg"

chown -R ga:ga "$MATERIALS_DIR"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Start ONLYOFFICE Presentation Editor
echo "Starting ONLYOFFICE Presentation Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:slide > /tmp/onlyoffice_pres_ga.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
sleep 2

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="