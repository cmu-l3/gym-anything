#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Medication History Reconstruction Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create source file 1: Pharmacy Partial Records
cat > "$WORKSPACE_DIR/pharmacy_partial_records.txt" << 'EOF'
PHARMACY PRINTOUT - Last 24 months only

2024-01-15: Propranolol 40mg, #60, Dr. Williams
2024-01-15: Escitalopram 10mg, #30, Dr. Williams  
2023-10-03: Propranolol 40mg, #60, Dr. Williams
2023-10-03: Escitalopram 10mg, #30, Dr. Williams
2023-07-12: Propranolol 20mg, #60, Dr. Williams [DOSAGE CHANGED FROM PREVIOUS]
2023-07-12: Escitalopram 10mg, #30, Dr. Williams
2023-04-20: Sumatriptan 50mg, #9, Dr. Williams [rescue medication]
2023-04-01: Propranolol 20mg, #60, Dr. Williams
2023-04-01: Escitalopram 10mg, #30, Dr. Williams

RECORDS PRIOR TO APRIL 2023 NOT AVAILABLE IN SYSTEM
EOF

# Create source file 2: Old Pill Bottles Notes
cat > "$WORKSPACE_DIR/old_pill_bottles_notes.txt" << 'EOF'
PILL BOTTLES FOUND IN MEDICINE CABINET:

1. Propranolol 40mg - Dr. Williams - Filled 01/15/2024 - "for migraine prevention" - bottle 3/4 full, still taking

2. Escitalopram 10mg - Dr. Williams - Filled 01/15/2024 - "for anxiety" - bottle 2/3 full, still taking

3. OLD BOTTLE (expired): Topiramate 50mg - Dr. Garcia - Filled 06/2022 - label says "take one daily for migraine prevention" - EMPTY

4. OLD BOTTLE (expired): Amitriptyline 25mg - Dr. Garcia - Filled 09/2021 - "for migraine, take at bedtime" - EMPTY

5. Sumatriptan 50mg - Dr. Williams - Filled 04/2023 - "take as needed for migraine" - still using occasionally
EOF

# Create source file 3: Calendar and Insurance Notes
cat > "$WORKSPACE_DIR/calendar_insurance_notes.txt" << 'EOF'
CALENDAR ENTRIES & INSURANCE EOB FRAGMENTS:

Nov 2021: "Started new migraine medication today (A-something?), Dr. Garcia said take at night"

Feb 2022: "Amitriptyline making me too drowsy, can barely function at work. Called Dr office."

March 2022: "Stopping the A- med, Dr switching me to Topiramate"

May 2022: "New topiramate dose - 50mg now instead of 25mg"

Jan 2023: "Topiramate side effects terrible - tingling in hands, can't think straight, food tastes weird"

Feb 2023: "Dr Garcia referred me to Dr Williams (new neurologist). Stopping topiramate."

March 2023: "Dr Williams starting me on propranolol 20mg twice daily + continuing my escitalopram"

July 2023: "Propranolol increased to 40mg - migraines down from 15/month to 6/month!"

---

INSURANCE EOB (2022): 
- Topiramate 25mg - filled June 2022
- Topiramate 50mg - filled August 2022, October 2022

INSURANCE EOB (2021):
- Amitriptyline 25mg - September 2021, November 2021, January 2022
EOF

# Create source file 4: Patient Memory Notes
cat > "$WORKSPACE_DIR/patient_memory_notes.txt" << 'EOF'
SARAH'S NOTES & MEMORIES:

- I've been on escitalopram for my anxiety since around 2020 or 2021 (Dr. Martinez prescribed it originally). Dose has always been 10mg. It works well, no major side effects.

- Before amitriptyline, I tried another antidepressant for migraines... sertraline? (Zoloft?) That was mid-2021. Made my anxiety worse. Only took it for about 6 weeks.

- The topiramate was AWFUL. I felt stupid all the time. Couldn't remember words. My hands and feet tingled constantly. Everything carbonated tasted flat. I stopped in January 2023 after 8 months.

- Propranolol has been amazing for preventing migraines. Started at 20mg twice daily, now 40mg twice daily since July 2023.

- I take sumatriptan (50mg) when I do get a migraine. Usually need it 3-6 times per month now, down from 15+ times before propranolol.

SPOUSE'S NOTES:
- The amitriptyline made you SO sleepy. You were sleeping 12 hours and still exhausted. That's why you switched in early 2022.
- You had a bad reaction to something Dr. Martinez prescribed in 2020 - broke out in hives. It was for sleep? Trazodone? You only took it twice.

DRUG ALLERGIES/BAD REACTIONS:
- Trazodone - hives after second dose (2020)
- Sertraline - worsened anxiety, heart palpitations (2021)
EOF

# Change ownership of source files
chown ga:ga "$WORKSPACE_DIR"/*.txt

echo "✅ Source files created:"
echo "   - pharmacy_partial_records.txt"
echo "   - old_pill_bottles_notes.txt"
echo "   - calendar_insurance_notes.txt"
echo "   - patient_memory_notes.txt"

# Create the initial starter document
DOC_PATH="$WORKSPACE_DIR/medication_history_sarah_chen.docx"

cat > /tmp/create_med_history_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add a title
title = doc.add_heading('Medication History', level=1)

# Add brief instructions
doc.add_paragraph("")
doc.add_paragraph("Patient: Sarah Chen")
doc.add_paragraph("Date of Birth: March 15, 1988")
doc.add_paragraph("")
doc.add_paragraph("Instructions: Review the four source files in this directory and create a comprehensive medication history document with the following sections:")
doc.add_paragraph("1. Current Medications")
doc.add_paragraph("2. Past Medications (Discontinued)")
doc.add_paragraph("3. Allergies and Adverse Reactions")
doc.add_paragraph("4. Notes for Provider (optional)")
doc.add_paragraph("")
doc.add_paragraph("--- BEGIN YOUR MEDICATION HISTORY BELOW ---")
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_med_history_doc.py
python3 /tmp/create_med_history_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Starter document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_med_history_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_med_history_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Medication History Reconstruction Task Setup Complete ==="
echo ""
echo "📋 TASK CONTEXT:"
echo "   Sarah Chen is switching to a new doctor after her practice closed."
echo "   She needs a comprehensive medication history for her appointment in 3 days."
echo ""
echo "📁 SOURCE FILES (in $WORKSPACE_DIR):"
echo "   1. pharmacy_partial_records.txt - Pharmacy data from 2023-2024"
echo "   2. old_pill_bottles_notes.txt - Information from pill bottles"
echo "   3. calendar_insurance_notes.txt - Calendar entries and insurance statements"
echo "   4. patient_memory_notes.txt - Patient's recollections and notes"
echo ""
echo "✏️  YOUR TASK:"
echo "   Review all four source files and create a comprehensive medication history"
echo "   document with clearly organized sections for:"
echo "   - Current Medications (at least 2 with dosages and frequencies)"
echo "   - Past Medications (at least 4 with dates and reasons for discontinuation)"
echo "   - Allergies/Adverse Reactions (at least 1 documented)"
echo "   - Use clear section headings (bold or Heading styles)"
echo "   - Save the document when complete (Ctrl+S)"
echo ""
echo "⏱️  Estimated time: 8-12 minutes"