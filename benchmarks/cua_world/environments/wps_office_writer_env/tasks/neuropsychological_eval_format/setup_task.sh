#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Neuropsychological Evaluation Format Task ==="

# Create necessary directories
sudo -u ga mkdir -p /home/ga/Documents/results
sudo -u ga mkdir -p /home/ga/Desktop

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the raw dictation document using Python
python3 << 'PYEOF'
from docx import Document

doc = Document()

# Add unformatted raw text
doc.add_paragraph("NEUROPSYCHOLOGICAL EVALUATION REPORT")
doc.add_paragraph("Patient Name: John Doe")
doc.add_paragraph("DOB: 05/14/1965")
doc.add_paragraph("MRN: 8492-491")
doc.add_paragraph("Date of Exam: 10/24/2025")
doc.add_paragraph("Evaluator: Dr. Sarah Jenkins")

doc.add_paragraph("[NOTE TO TYPIST: Please format the demographics at the top of the page nicely into a clear header block]")

doc.add_paragraph("Reason for Referral")
doc.add_paragraph("Mr. Doe is a 60-year-old right-handed male referred by his primary care physician to evaluate memory complaints and rule out early-onset Alzheimer's disease.")

doc.add_paragraph("Background and History")
doc.add_paragraph("The patient reports a 2-year history of progressive short-term memory decline. [DICTATOR NOTE: delete this sentence about the patient's dog, it's not relevant. The patient brought a golden retriever to the clinic today.] He denies any history of traumatic brain injury, seizures, or stroke. He has a family history of dementia on his maternal side.")

doc.add_paragraph("Behavioral Observations")
doc.add_paragraph("Mr. Doe was fully alert and cooperative throughout the evaluation. Effort testing indicated excellent engagement. Speech was fluent but characterized by occasional word-finding difficulties.")

doc.add_paragraph("Tests Administered")
doc.add_paragraph("Wechsler Adult Intelligence Scale - Fourth Edition (WAIS-IV), Wechsler Memory Scale - Fourth Edition (WMS-IV), Trail Making Test Parts A and B, Boston Naming Test.")

doc.add_paragraph("Test Results")
doc.add_paragraph("The patient was administered the WAIS-IV. The Verbal Comprehension Index was 98 (45th percentile, Average). The Perceptual Reasoning Index was 85 (16th percentile, Low Average). Working Memory Index was 92 (30th percentile, Average). Processing Speed Index was 81 (10th percentile, Low Average). On the WMS-IV, Auditory Memory was 88 (21st percentile, Low Average), and Visual Memory was 82 (12th percentile, Low Average). Trail Making Test Part A was completed in 45 seconds (Standard Score 90, 25th percentile, Average). Trail Making Test Part B was completed in 120 seconds (Standard Score 75, 5th percentile, Borderline).")

doc.add_paragraph("[NOTE TO TYPIST: format the following scores as a table with columns for Test Domain, Index/Subtest, Standard Score, Percentile, and Qualitative Description. The Domains should be WAIS-IV, WMS-IV, and Trail Making Test.]")

doc.add_paragraph("Summary and Impressions")
doc.add_paragraph("Overall cognitive profile is characterized by average verbal abilities with relative weaknesses in processing speed, executive functioning, and delayed recall for visual material.")

doc.add_paragraph("Diagnostic Impressions")
doc.add_paragraph("Mild Neurocognitive Disorder, likely due to Alzheimer's disease. (ICD-10: G31.84, F06.70)")

doc.add_paragraph("Recommendations")
doc.add_paragraph("1. Follow up with neurology for possible initiation of acetylcholinesterase inhibitors.\n2. Consider participating in clinical trials for early-stage Alzheimer's.\n3. Return for repeat neuropsychological testing in 12-18 months to monitor trajectory.")

doc.save("/home/ga/Documents/raw_neuropsych_eval.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/raw_neuropsych_eval.docx
sudo chmod 644 /home/ga/Documents/raw_neuropsych_eval.docx

# Start WPS Writer with the file
if ! pgrep -f "wps" > /dev/null; then
    echo "Starting WPS Writer..."
    su - ga -c "DISPLAY=:1 wps /home/ga/Documents/raw_neuropsych_eval.docx &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "WPS Writer" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        echo "WPS Writer window found: $WID"
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Dismiss any popup dialogs
dismiss_wps_dialogs || true

# Re-focus
DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="