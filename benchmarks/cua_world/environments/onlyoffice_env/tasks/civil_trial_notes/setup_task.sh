#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Civil Trial Notes Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial unstructured document with raw notes
DOC_PATH="$WORKSPACE_DIR/trial_notes_template.docx"

cat > /tmp/create_trial_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add title
title = doc.add_paragraph("Jury Duty Notes - Unorganized")
title.runs[0].font.size = Pt(16)
title.runs[0].bold = True

doc.add_paragraph("")

# Add raw unstructured content that needs to be organized
doc.add_paragraph("CASE INFORMATION:")
doc.add_paragraph("Martinez v. Chen - Case number CV-2024-8847. I'm Juror #7. Trial dates are March 18-21, 2024.")

doc.add_paragraph("")
doc.add_paragraph("WHAT THIS CASE IS ABOUT:")
doc.add_paragraph("Plaintiff Martinez claims defendant Chen ran a red light at Oak and Maple intersection on March 3rd, causing a T-bone collision. Martinez suffered injuries requiring surgery, missed 8 weeks of work, and is suing for damages including medical expenses and lost wages. Defendant Chen argues the light was yellow when he entered the intersection and that Martinez was speeding. Chen claims Martinez contributed to the accident.")

doc.add_paragraph("")
doc.add_paragraph("WITNESSES - NEED TO ORGANIZE:")
doc.add_paragraph("Sarah Kim testified for plaintiff, was on stand about 45 minutes. She said she clearly saw defendant's car speed through a red light and heard brakes screeching after the impact. She seemed very confident, no hesitation in her answers.")

doc.add_paragraph("David Park testified for defense, about 30 minutes. He said the light was yellow when defendant entered intersection and that plaintiff was going very fast. During cross-examination he disclosed he worked with defendant previously.")

doc.add_paragraph("Officer Rodriguez testified for plaintiff, 50 minutes. Professional demeanor, referred to his notes frequently. He said he arrived 8 minutes after the crash. Defendant stated to him 'I didn't see the light change'. Officer noted there were no skid marks from defendant's vehicle.")

doc.add_paragraph("Dr. Ellen Watkins testified for plaintiff, 35 minutes on stand. Medical expert who treated Martinez. She said plaintiff's injuries were consistent with a T-bone collision, required surgery, and resulted in 8 weeks of lost work. She was very thorough in her testimony.")

doc.add_paragraph("")
doc.add_paragraph("EVIDENCE PRESENTED:")
doc.add_paragraph("Plaintiff showed us: P-1 was intersection photos showing the traffic light configuration. P-2 was medical records from County Hospital showing the surgery and treatment. P-3 was police report #2024-1847 documenting the scene. P-4 was plaintiff's pay stubs showing lost wages.")

doc.add_paragraph("Defendant showed us: D-1 was defendant's dash cam video but the timestamp was disputed by plaintiff's attorney. D-2 was weather report showing bright sun conditions that day which could cause glare. D-3 was a traffic study showing average speeds on Maple Avenue.")

doc.add_paragraph("")
doc.add_paragraph("TIMELINE OF THE ACCIDENT - March 3, 2024:")
doc.add_paragraph("According to testimony, around 2:35 PM defendant was approaching the intersection on Oak Street heading north. At 2:36 PM plaintiff was driving west on Maple Avenue. The big dispute is about 2:36 PM regarding the traffic light status - Kim (plaintiff witness) says it was definitely red for defendant, but Park (defendant witness) says it was yellow. The collision occurred at 2:36-2:37 PM in the middle of the intersection. Officer Rodriguez arrived at the scene at 2:45 PM. Ambulance arrived at 2:50 PM and transported plaintiff to County Hospital.")

doc.add_paragraph("")
doc.add_paragraph("THINGS THAT DON'T ADD UP:")
doc.add_paragraph("1. Traffic light contradiction - Plaintiff's witness Kim said definitely red, defendant's witness Park said yellow, but there's no traffic camera at that intersection to verify who's right.")

doc.add_paragraph("2. The skid marks issue - Officer Rodriguez said there were no skid marks from defendant's vehicle, but defendant claims he braked. Why no skid marks if he braked?")

doc.add_paragraph("3. Witness credibility - David Park disclosed he previously worked with defendant Chen. How reliable is his testimony given their prior relationship?")

doc.add_paragraph("4. The dash cam timestamp - Defendant's dash cam video shows the incident but plaintiff's attorney challenged the timestamp saying it could have been altered. Which version is accurate?")

doc.add_paragraph("")
doc.add_paragraph("QUESTIONS I NEED TO DISCUSS IN DELIBERATION:")
doc.add_paragraph("Why was there no skid mark from defendant if they claim to have braked?")
doc.add_paragraph("How much weight should we give to Park's testimony given he worked with defendant?")
doc.add_paragraph("Does sun glare reasonably explain failure to see the light, or does it indicate negligence?")
doc.add_paragraph("If the light was yellow, does that automatically make defendant not liable?")
doc.add_paragraph("Are the medical expenses and lost wages calculations reasonable?")

doc.add_paragraph("")
doc.add_paragraph("===== END OF RAW NOTES =====")
doc.add_paragraph("TODO: Organize all this information into a proper structured document with clear sections, witness table, timeline, and analysis.")

doc.save(sys.argv[1])
print(f"Trial notes template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_trial_doc.py
python3 /tmp/create_trial_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Trial notes template created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_trial_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_trial_task.log || true
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

echo "=== Civil Trial Notes Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Transform the unstructured notes into a properly organized document:"
echo "  1. Add document header: Civil Trial Notes - Martinez v. Chen"
echo "  2. Include case number CV-2024-8847 and Juror #7"
echo "  3. Create Case Summary section"
echo "  4. Create Witness Testimony TABLE with 5 columns (Witness Name, Side, Time, Key Points, Credibility)"
echo "  5. Add 4 witness entries (Kim, Park, Rodriguez, Watkins) with bold names"
echo "  6. Create Evidence Presented section with Plaintiff's and Defendant's exhibits"
echo "  7. Create Timeline of Events with time markers and mark disputes in italics"
echo "  8. Create Contradictions to Resolve section with numbered items"
echo "  9. Create Questions for Deliberation section"
echo "  10. Save the document (Ctrl+S)"