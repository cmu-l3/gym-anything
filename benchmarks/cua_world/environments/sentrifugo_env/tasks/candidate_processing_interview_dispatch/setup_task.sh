#!/bin/bash
echo "=== Setting up candidate_processing_interview_dispatch task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Clean up any prior task data from ATS tables to ensure clean slate
echo "Cleaning up ATS database tables..."
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "TRUNCATE TABLE main_candidates;" 2>/dev/null || true
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "TRUNCATE TABLE main_interviewschedule;" 2>/dev/null || true

# Ensure the "Lead Social Worker" job title exists
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "INSERT IGNORE INTO main_jobtitles (jobtitlecode, jobtitlename, description, isactive) VALUES ('LSW', 'Lead Social Worker', 'Lead Social Worker role', 1);" 2>/dev/null || true

# Create candidate PDF resumes using ReportLab
echo "Generating candidate resumes..."
cat > /tmp/make_resumes.py << 'EOF'
import os
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

def make_resume(filename, name, email, cred, exp):
    c = canvas.Canvas(filename, pagesize=letter)
    c.setFont("Helvetica-Bold", 16)
    c.drawString(72, 720, name)
    c.setFont("Helvetica", 12)
    c.drawString(72, 700, email)
    
    c.setFont("Helvetica-Bold", 14)
    c.drawString(72, 650, "Credentials & Certifications")
    c.setFont("Helvetica", 12)
    c.drawString(72, 630, cred)
    
    c.setFont("Helvetica-Bold", 14)
    c.drawString(72, 580, "Experience")
    c.setFont("Helvetica", 12)
    c.drawString(72, 560, exp)
    c.save()

dest = "/home/ga/Desktop/New_Applicants"
os.makedirs(dest, exist_ok=True)

# Unqualified: Expired LCSW
make_resume(os.path.join(dest, "resume_rodriguez_elena.pdf"), "Elena Rodriguez", "elena.r@example.com", 
            "LCSW - Licensed Clinical Social Worker (Expired 2024)", "5 years at Community Health Center")

# Unqualified: No LCSW
make_resume(os.path.join(dest, "resume_chen_marcus.pdf"), "Marcus Chen", "marcus.c@example.com", 
            "MSW - Master of Social Work", "3 years at City Services")

# Qualified: Active LCSW
make_resume(os.path.join(dest, "resume_washington_sarah.pdf"), "Sarah Washington", "sarah.w@example.com", 
            "LCSW - Licensed Clinical Social Worker (Active, #99482)", "7 years at General Hospital")
EOF
python3 /tmp/make_resumes.py
chown -R ga:ga /home/ga/Desktop/New_Applicants

# Create the hiring directive document
cat > /home/ga/Desktop/hiring_directive.txt << 'EOF'
URGENT: Lead Social Worker Hiring

We have received three applicants for the "Lead Social Worker" position:
1. Elena Rodriguez
2. Marcus Chen
3. Sarah Washington

Their resumes are located in the "New_Applicants" folder on the Desktop.

ACTIONS REQUIRED:
1. Navigate to Talent Acquisition > Candidates in Sentrifugo.
2. Add all three candidates to the system, selecting "Lead Social Worker" as their Job Title.
3. Upload their PDF resumes to their candidate profiles.
4. Read their resumes carefully. Per state compliance laws, we can ONLY interview candidates who hold an **Active** Licensed Clinical Social Worker (LCSW) credential.
5. Identify the single qualified candidate.
6. Navigate to Talent Acquisition > Interview Schedule.
7. Schedule a "First Round" interview ONLY for the qualified candidate. Assign the interview to any available Hiring Manager for next Thursday at 10:00 AM.
EOF
chown ga:ga /home/ga/Desktop/hiring_directive.txt

# Log in to Sentrifugo and navigate to Talent Acquisition
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/talentacquisition"
sleep 4

# Take initial screenshot showing clean state
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="