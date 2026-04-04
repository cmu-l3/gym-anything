#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up ADA Accommodation Request Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/ADA_Request"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create reference file 1: Medical notes
cat > "$WORKSPACE_DIR/medical_notes.txt" << 'EOF'
Dr. Sarah Chen, MD - Neurology Clinic
Patient Documentation Summary

Diagnosis: Chronic migraine disorder with photosensitivity
ICD-10: G43.709

Clinical Notes:
Patient experiences 12-15 migraine days per month, significantly impacting daily functioning.
Primary triggers identified:
- Fluorescent and bright LED lighting
- Prolonged screen exposure (>2 hours continuous)
- Irregular sleep patterns and early morning schedules

Functional Limitations:
- Difficulty maintaining focus during migraine episodes
- Photophobia (light sensitivity) causing eye strain and pain
- Reduced productivity in bright office environments
- Morning medication schedule requires consistent timing

Medical Recommendations:
Workplace modifications recommended to reduce trigger exposure:
- Alternative lighting options (warm spectrum, lower intensity)
- Screen filters and ergonomic monitor positioning
- Flexible scheduling to accommodate medication timing
- Ability to work in low-stimulus environment during prodrome/onset phases
- Regular breaks during computer-intensive tasks

Patient is currently employed and motivated to maintain work performance with appropriate
workplace accommodations as permitted under ADA guidelines.

Date: December 15, 2024
Provider: Dr. Sarah Chen, MD, Neurology
EOF

# Create reference file 2: Accommodation examples
cat > "$WORKSPACE_DIR/accommodation_examples.txt" << 'EOF'
Sample Reasonable Accommodations for Light-Sensitive Conditions

LIGHTING MODIFICATIONS:
- Desk lamp with adjustable warm-spectrum lighting to replace overhead fluorescents
- Window blinds or position adjustment to control natural light
- Motion sensor override for automatic lighting in workspace area
- Lamp shields or diffusers to reduce glare

EQUIPMENT & ERGONOMICS:
- Anti-glare screen filter for computer monitor
- Monitor positioning away from windows/bright sources
- Blue light filtering software (f.lux, Windows Night Light)
- Ergonomic desk setup consultation

SCHEDULE FLEXIBILITY:
- Flexible start time (9:30am instead of 8:00am) to accommodate morning medication routine
- Option for compressed work week or adjusted hours
- Permission to work from home 1-2 days/week during severe episodes
- Ability to use sick time in smaller increments (half-days) during migraine onset

WORKSPACE MODIFICATIONS:
- Quiet workspace away from high-traffic common areas
- Cubicle or office with door for light/noise control during episodes
- Permission to wear tinted glasses indoors when needed
- Access to wellness room for breaks during prodrome symptoms

WORK PROCESS ADJUSTMENTS:
- Email communication option during meetings when experiencing active migraine
- Recording or notes from missed portions of meetings
- Break flexibility during long computer work sessions (5-10 min every hour)
- Deadline extensions during documented medical episodes

Note: These are examples. Specific accommodations should be tailored to individual
needs and job requirements through interactive process with employer.
EOF

# Create reference file 3: ADA rights summary
cat > "$WORKSPACE_DIR/ada_rights_summary.txt" << 'EOF'
ADA Reasonable Accommodation: Employee Rights Summary

WHAT IS THE ADA?
The Americans with Disabilities Act (ADA) is a federal civil rights law that prohibits
discrimination against individuals with disabilities in all areas of public life,
including employment.

WHO IS COVERED?
- Employees with physical or mental impairments that substantially limit one or more
  major life activities
- Individuals with a record of such impairment
- Individuals regarded as having such impairment
- Employers with 15 or more employees are covered

WHAT ARE REASONABLE ACCOMMODATIONS?
Modifications or adjustments to a job, work environment, or application process that
enable a qualified individual with a disability to:
- Perform essential job functions
- Enjoy equal benefits and privileges of employment
- Have equal access to employment opportunities

EMPLOYER OBLIGATIONS:
- Must provide reasonable accommodations unless it creates "undue hardship"
- Must engage in "interactive process" - good faith discussion with employee
- Cannot retaliate against employee for requesting accommodation
- Must keep medical information confidential

EMPLOYEE RESPONSIBILITIES:
- Inform employer of need for accommodation (can be informal initially)
- Provide medical documentation if requested
- Participate in interactive process discussion
- Suggest specific accommodations (though employer can propose alternatives)

WHAT IS "UNDUE HARDSHIP"?
Accommodation is not required if it causes significant difficulty or expense considering:
- Nature and cost of accommodation
- Overall financial resources of the employer
- Impact on business operations

FORMAL REQUEST PROCESS:
1. Submit written request describing need and suggesting accommodations
2. Provide medical documentation verifying condition and limitations
3. Engage in interactive process with HR/management
4. Work together to identify effective, reasonable accommodations
5. Implement agreed-upon accommodations with trial period if needed

RESOURCES:
- Job Accommodation Network (JAN): askjan.org
- EEOC ADA Information: eeoc.gov/ada
- Disability Rights Legal Center
EOF

# Create reference file 4: Job duties and current challenges
cat > "$WORKSPACE_DIR/job_duties.txt" << 'EOF'
Current Position: Marketing Coordinator
Department: Marketing & Communications
Employment Status: Full-time, Exempt

ESSENTIAL JOB FUNCTIONS:
1. Social Media Content Creation (40% of time)
   - Create graphics, videos, and written content for social platforms
   - 4-6 hours daily screen time for design and editing work
   - Use of Adobe Creative Suite, Canva, video editing tools

2. Campaign Management & Analytics (25% of time)
   - Monitor social media metrics and engagement
   - Prepare weekly/monthly performance reports
   - Coordinate with external vendors and influencers

3. Team Collaboration (20% of time)
   - Attend daily stand-up meetings (9:00am)
   - Weekly marketing team meetings
   - Cross-functional project collaboration
   - Client presentations (occasional)

4. Content Calendar Management (15% of time)
   - Plan and schedule content 2-4 weeks in advance
   - Coordinate with other departments for content approval
   - Manage deadlines and deliverables

CURRENT WORK ENVIRONMENT:
- Open office floor plan with 40+ employees
- Bright overhead fluorescent lighting throughout
- Assigned desk in high-traffic area near conference rooms
- Fixed schedule: 8:00am - 5:00pm, Monday-Friday
- Primarily on-site work (remote work not currently offered)

CURRENT CHALLENGES DUE TO MEDICAL CONDITION:
1. Lighting Triggers:
   - Overhead fluorescent lights trigger migraines within 2-3 hours
   - Eye strain and headaches worsen throughout day
   - Unable to maintain productivity during afternoon hours

2. Schedule Conflicts:
   - 8:00am start time conflicts with medication timing (taken at 7:30am, needs 60-90min to take effect)
   - Arriving with residual morning grogginess reduces effectiveness in early meetings

3. Extended Screen Time:
   - 4-6 hours of continuous design work under current lighting exacerbates symptoms
   - Lack of structured breaks leads to prolonged exposure to triggers

4. Work Disruption:
   - Currently missing 3-4 full workdays per month due to severe migraine episodes
   - Productivity significantly reduced on 6-8 additional days per month

IMPACT ON PERFORMANCE:
- Missing deadlines during migraine episodes
- Reduced quality of work during pain/prodrome periods
- Decreased attendance affecting team collaboration
- Difficulty maintaining focus in afternoon meetings
- Overall job performance below personal standards despite strong motivation

DESIRED OUTCOME:
With appropriate accommodations, expect to:
- Reduce missed workdays from 3-4 to 0-1 per month
- Maintain consistent productivity throughout work day
- Improve quality and timeliness of deliverables
- Continue contributing to team objectives effectively
EOF

# Set proper ownership for all reference files
chown ga:ga "$WORKSPACE_DIR"/*.txt

echo "✅ Reference files created in: $WORKSPACE_DIR"
ls -lh "$WORKSPACE_DIR"

# Create a starter document template with basic structure
DOC_PATH="$WORKSPACE_DIR/accommodation_request.docx"

cat > /tmp/create_ada_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add a minimal template to give the agent a starting point
doc.add_paragraph("")
doc.add_paragraph("TO: Human Resources Department")
doc.add_paragraph("FROM: [Your Name]")
doc.add_paragraph("DATE: [Today's Date]")
doc.add_paragraph("RE: [Subject]")
doc.add_paragraph("")
doc.add_paragraph("[Begin your letter here...]")
doc.add_paragraph("")
doc.add_paragraph("")
doc.add_paragraph("[Review the reference files in this folder for guidance]")

doc.save(sys.argv[1])
print(f"Document template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_ada_doc.py
python3 /tmp/create_ada_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document template created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_ada_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_ada_task.log || true
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

echo "=== ADA Accommodation Request Task Setup Complete ==="
echo ""
echo "📁 Reference files available in: $WORKSPACE_DIR"
echo "  - medical_notes.txt (doctor's documentation)"
echo "  - accommodation_examples.txt (sample accommodations)"
echo "  - ada_rights_summary.txt (legal rights information)"
echo "  - job_duties.txt (current job and challenges)"
echo ""
echo "📝 Task Requirements:"
echo "  1. Review the 4 reference text files"
echo "  2. Create formal business letter structure"
echo "  3. Include subject line mentioning ADA/accommodation"
echo "  4. Add section explaining medical condition (reference documentation)"
echo "  5. Add section with at least 3 specific accommodation requests"
echo "  6. Add section explaining how accommodations help job performance"
echo "  7. Include closing requesting a meeting to discuss"
echo "  8. Apply professional formatting (bold headers, proper spacing)"
echo "  9. Save document as: accommodation_request.docx"
echo ""
echo "💡 Tip: Balance providing enough medical information with maintaining privacy"