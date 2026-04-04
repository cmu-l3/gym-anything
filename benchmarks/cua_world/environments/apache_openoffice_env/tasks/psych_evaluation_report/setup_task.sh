#!/bin/bash
set -e
echo "=== Setting up Psychological Evaluation Report Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare User Directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/Confidential_Psych_Eval_Thorne_M.odt 2>/dev/null || true
rm -f /home/ga/Documents/patient_intake.json 2>/dev/null || true

# 3. Create Patient Data JSON
cat > /home/ga/Documents/patient_intake.json << 'EOF'
{
  "patient": {
    "name": "Marcus Thorne",
    "dob": "2012-05-14",
    "age": 12,
    "grade": "6th",
    "school": "Lincoln Middle School"
  },
  "referral": {
    "source": "Dr. Sarah Jenkins, Pediatrician",
    "reason": "Evaluation for attention difficulties, impulsivity, and academic underperformance in mathematics."
  },
  "wisc_v_scores": [
    {"index": "Verbal Comprehension (VCI)", "score": 112, "percentile": 79, "classification": "High Average"},
    {"index": "Visual Spatial (VSI)", "score": 98, "percentile": 45, "classification": "Average"},
    {"index": "Fluid Reasoning (FRI)", "score": 105, "percentile": 63, "classification": "Average"},
    {"index": "Working Memory (WMI)", "score": 88, "percentile": 21, "classification": "Low Average"},
    {"index": "Processing Speed (PSI)", "score": 85, "percentile": 16, "classification": "Low Average"}
  ],
  "behavioral_observations": "Marcus was cooperative but demonstrated motor restlessness. He frequently interrupted tasks to ask unrelated questions.",
  "diagnosis": {
    "code_icd10": "F90.2",
    "code_dsm5": "314.01",
    "name": "Attention-Deficit/Hyperactivity Disorder, Combined Presentation",
    "specifiers": "Moderate severity"
  }
}
EOF
chown ga:ga /home/ga/Documents/patient_intake.json
chmod 644 /home/ga/Documents/patient_intake.json

# 4. Create Desktop Shortcut for Writer (if not exists)
if [ ! -f /home/ga/Desktop/openoffice-writer.desktop ]; then
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
MimeType=application/vnd.oasis.opendocument.text;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# 5. Record Start Time and Initial State
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists

# 6. Ensure OpenOffice is NOT running (clean slate)
pkill -f soffice 2>/dev/null || true

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Data file created at: /home/ga/Documents/patient_intake.json"