#!/bin/bash
set -e
echo "=== Setting up Child Welfare Case Plan Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/Martinez_Family_Case_Plan.odt 2>/dev/null || true
rm -f /home/ga/Documents/family_assessment.json 2>/dev/null || true

# 3. Create the input JSON file with realistic family data
cat > /home/ga/Documents/family_assessment.json << 'EOF'
{
  "agency": {
    "name": "Kentucky Cabinet for Health and Family Services",
    "division": "Department for Community Based Services (DCBS)",
    "region": "Jefferson County (Salt River Trail Region)",
    "office_address": "908 West Broadway, Louisville, KY 40203",
    "phone": "(502) 595-4550"
  },
  "case_info": {
    "case_number": "JC-2024-0847-JCFC",
    "court": "Jefferson County Family Court",
    "division": "Division 12",
    "judge": "Hon. Patricia A. Willoughby",
    "case_type": "Dependency, Neglect, and Abuse (DNA)",
    "legal_basis": "KRS 600.020(1)(a)(2) — Neglect: inadequate supervision",
    "date_filed": "2024-09-12",
    "case_plan_due_date": "2024-10-12"
  },
  "assigned_workers": {
    "social_worker": {
      "name": "Keisha Renee Washington",
      "credentials": "MSW, LCSW",
      "phone": "(502) 595-4550 ext. 2247",
      "email": "keisha.washington@ky.gov"
    },
    "supervisor": "Anthony Paul DiNapoli, MSW"
  },
  "family_members": [
    {
      "name": "Elena Teresa Martinez",
      "relationship": "Mother (Custodial Parent)",
      "dob": "1990-04-18",
      "address": "2847 Poplar Creek Drive, Apt 6B, Louisville, KY 40216",
      "phone": "(502) 555-0194"
    },
    {
      "name": "Ricardo Alejandro Gutierrez",
      "relationship": "Father (Non-Custodial)",
      "dob": "1987-11-02",
      "address": "1530 South 4th Street, Apt 12, Louisville, KY 40208"
    },
    { "name": "Sofia Lucia Martinez", "relationship": "Child", "dob": "2016-06-29", "age": 8 },
    { "name": "Diego Rafael Martinez", "relationship": "Child", "dob": "2019-03-14", "age": 5 },
    { "name": "Isabella Marie Martinez", "relationship": "Child", "dob": "2022-08-05", "age": 2 }
  ],
  "allegation_narrative": "On September 8, 2024, DCBS received a referral reporting inadequate supervision. Ms. Martinez left three children (ages 8, 5, 2) unsupervised overnight. Home conditions indicated food insecurity and hygiene concerns. Neglect substantiated on September 11, 2024.",
  "assessment_summary": {
    "strengths": [
      "Mother cooperative with DCBS",
      "Children bonded with parents",
      "Father engaged and paying support",
      "Maternal grandmother available for emergency support"
    ],
    "concerns": [
      "Inadequate supervision/judgment",
      "Chronic school absenteeism (Sofia)",
      "Home hygiene and food security",
      "Possible substance use issues"
    ]
  },
  "case_plan_goals": [
    {
      "goal_number": 1,
      "goal": "Ensure Safe and Stable Housing Environment",
      "objectives": "Maintain clean home; apply for SNAP/utility assistance",
      "measure": "Monthly home visits; proof of applications",
      "target_date": "2025-01-16"
    },
    {
      "goal_number": 2,
      "goal": "Complete Parenting Education Program",
      "objectives": "Complete 'Nurturing Parenting Program' (16 weeks)",
      "measure": "Certificate of completion",
      "target_date": "2025-02-28"
    },
    {
      "goal_number": 3,
      "goal": "Complete Substance Abuse Assessment",
      "objectives": "Assessment at Seven Counties Services; comply with recommendations",
      "measure": "Assessment report; negative screens",
      "target_date": "Ongoing"
    },
    {
      "goal_number": 4,
      "goal": "Improve Children's School Attendance",
      "objectives": "Sofia to attend 95% of school days; Diego evaluation for speech",
      "measure": "Quarterly attendance reports",
      "target_date": "2025-06-30"
    }
  ],
  "service_referrals": [
    {
      "provider": "Volunteers of America Mid-States",
      "service": "Family Stabilization Program",
      "contact": "Jennifer Kwan (502) 636-0771"
    },
    {
      "provider": "Centerstone Kentucky",
      "service": "Substance abuse assessment",
      "contact": "Intake (502) 589-1100"
    },
    {
      "provider": "JCPS Family Resource Center",
      "service": "Attendance monitoring, supplies",
      "contact": "Danielle Price (502) 485-8345"
    },
    {
      "provider": "Home of the Innocents",
      "service": "Parenting classes",
      "contact": "Parenting Dept (502) 596-1000"
    },
    {
      "provider": "Neighborhood Place South",
      "service": "Supervised visitation",
      "contact": "Front Desk (502) 485-6360"
    }
  ],
  "visitation_schedule": {
    "non_custodial_parent": "Ricardo Gutierrez",
    "location": "Neighborhood Place South",
    "schedule": [
      { "day": "Tuesday", "time": "5:00 PM — 7:00 PM" },
      { "day": "Saturday", "time": "10:00 AM — 2:00 PM" }
    ],
    "conditions": "Must be supervised; father must provide snacks; no legal discussion"
  },
  "case_plan_structure": {
    "required_sections": [
      "Family Identification",
      "Case Information",
      "Reason for Court Involvement",
      "Assessment Summary",
      "Case Plan Goals and Objectives",
      "Service Referrals",
      "Visitation Schedule",
      "Signatures"
    ]
  }
}
EOF
chown ga:ga /home/ga/Documents/family_assessment.json
chmod 644 /home/ga/Documents/family_assessment.json

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenOffice Writer so it's ready (blank document)
echo "Launching OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "OpenOffice Writer"; then
            echo "Writer window detected"
            break
        fi
        sleep 1
    done
fi

# 6. Maximize and focus
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="