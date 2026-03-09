#!/bin/bash
# Setup script for special_education_iep_create task

echo "=== Setting up Special Education IEP Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any previous run artifacts
rm -f /home/ga/Documents/IEP_Reyes-Contreras_Mateo_2024.odt 2>/dev/null || true
rm -f /home/ga/Documents/student_iep_data.json 2>/dev/null || true

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists

# Create the student data JSON file
cat > /home/ga/Documents/student_iep_data.json << 'EOF'
{
  "document_info": {
    "document_type": "Individualized Education Program (IEP)",
    "school_district": "DeKalb County School District",
    "state": "Georgia",
    "school_year": "2024-2025",
    "meeting_date": "2024-11-15",
    "effective_date": "2024-11-15",
    "review_date": "2025-11-14"
  },
  "student": {
    "first_name": "Mateo",
    "last_name": "Reyes-Contreras",
    "dob": "2015-04-22",
    "grade": "4th",
    "student_id": "DCK-2024-08741",
    "school": "Lakewood Heights Elementary School"
  },
  "eligibility": {
    "category": "Specific Learning Disability (SLD)",
    "areas": ["Basic Reading Skills", "Reading Fluency", "Written Expression"]
  },
  "present_levels": {
    "reading": "Mateo reads at a mid-2nd grade level. DIBELS ORF score is 52 wpm (benchmark 112). Woodcock-Johnson Broad Reading SS is 78 (7th percentile). He struggles with multisyllabic words and vowel teams.",
    "writing": "Written expression is significantly below grade level (WJ-IV SS 72). Writing samples show phonetic spelling, lack of punctuation, and simple sentence structure.",
    "math": "Math is a relative strength. WJ-IV Broad Math SS 94 (34th percentile) is within average range.",
    "functional": "Mateo is social and follows routines but withdraws during reading tasks due to frustration."
  },
  "annual_goals": [
    {
      "area": "Reading Fluency",
      "goal": "By Nov 2025, Mateo will read 4th-grade passages at 90 wpm with 95% accuracy.",
      "objectives": ["Feb 2025: 65 wpm", "May 2025: 78 wpm"]
    },
    {
      "area": "Reading Comprehension",
      "goal": "By Nov 2025, Mateo will answer literal and inferential questions with 80% accuracy.",
      "objectives": ["Feb 2025: 75% literal", "May 2025: 65% inferential"]
    },
    {
      "area": "Written Expression",
      "goal": "By Nov 2025, Mateo will write a 5-paragraph essay scoring 3/4 on district rubric.",
      "objectives": ["Feb 2025: 3-sentence paragraph", "May 2025: 3-paragraph essay"]
    },
    {
      "area": "Spelling",
      "goal": "By Nov 2025, Mateo will spell 85% of grade-level high-frequency words correctly.",
      "objectives": ["Feb 2025: 70% accuracy", "May 2025: 80% punctuation accuracy"]
    }
  ],
  "services": [
    {"type": "Specialized Instruction - Reading", "location": "Resource Room", "frequency": "5x/week", "duration": "45 min"},
    {"type": "Specialized Instruction - Writing", "location": "Resource Room", "frequency": "3x/week", "duration": "30 min"},
    {"type": "Speech-Language Therapy", "location": "Speech Room", "frequency": "2x/week", "duration": "30 min"},
    {"type": "Occupational Therapy", "location": "OT Room", "frequency": "1x/week", "duration": "30 min"}
  ],
  "accommodations": [
    "Extended time (1.5x)",
    "Preferential seating",
    "Text-to-speech for content areas",
    "Graphic organizers for writing",
    "Small group testing",
    "Visual daily schedule"
  ],
  "lre_statement": "Mateo will participate in general education for 82% of the day. Removal is required only for intensive reading/writing intervention.",
  "iep_team": ["Ana Reyes (Parent)", "Yolanda Prescott (Special Ed)", "Marcus Chen (Gen Ed)", "Dr. Karen Whitfield (Psychologist)"]
}
EOF

chown ga:ga /home/ga/Documents/student_iep_data.json
chmod 644 /home/ga/Documents/student_iep_data.json

# Ensure OpenOffice desktop shortcut exists
mkdir -p /home/ga/Desktop
if [ -f "/usr/share/applications/openoffice4-writer.desktop" ]; then
    cp "/usr/share/applications/openoffice4-writer.desktop" /home/ga/Desktop/
    chmod +x /home/ga/Desktop/openoffice4-writer.desktop
    chown ga:ga /home/ga/Desktop/openoffice4-writer.desktop
fi

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Data file created at: /home/ga/Documents/student_iep_data.json"