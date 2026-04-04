#!/bin/bash
set -e
echo "=== Setting up Workplace Investigation Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents

# 1. Create the Case File JSON with realistic data
cat > /home/ga/Documents/case_file.json << 'EOF'
{
  "case_number": "PSS-EEO-2024-017",
  "case_type": "Workplace Harassment and Retaliation",
  "company": {
    "name": "Pinnacle Software Solutions, Inc.",
    "address": "8500 Shoal Creek Boulevard, Suite 300, Austin, TX 78757",
    "industry": "Enterprise Software Development",
    "employees": 487
  },
  "investigating_officer": {
    "name": "Sandra Okafor",
    "title": "Director of Compliance & Ethics",
    "department": "Legal and Compliance"
  },
  "dates": {
    "filed": "2024-03-11",
    "investigation_opened": "2024-03-13",
    "investigation_closed": "2024-04-19",
    "report_date": "2024-04-22"
  },
  "parties": {
    "complainant": {
      "name": "Elena Vargas",
      "title": "Senior UX Designer",
      "department": "Product Design",
      "tenure": "5 years"
    },
    "respondent": {
      "name": "Derek Haines",
      "title": "Engineering Manager",
      "department": "Platform Engineering",
      "tenure": "8 years"
    }
  },
  "witnesses": [
    {
      "name": "Tomoko Ishikawa",
      "title": "UX Research Lead",
      "summary": "Witnessed respondent interrupting complainant during sprint reviews on Jan 22. Heard respondent say 'maybe we should have someone more technical explain this'."
    },
    {
      "name": "Brian Jeffcoat",
      "title": "Senior Software Engineer",
      "summary": "Confirmed respondent made unprofessional comments about complainant ('typical designer thinking') at offsite event on Feb 8. Confirmed unjustified task reassignment."
    },
    {
      "name": "Lucia Mendes",
      "title": "HR Business Partner",
      "summary": "Received informal complaint from Vargas on Jan 8. Spoke to respondent on Jan 10 about respectful workplace expectations."
    },
    {
      "name": "Raj Patel",
      "title": "Product Manager",
      "summary": "Observed pattern of respondent questioning complainant's competence. Stated reassignment of tasks negatively impacted project timeline."
    }
  ],
  "evidence_inventory": [
    {"id": "EV-001", "type": "Slack Export", "date": "2024-03-14", "desc": "Screenshots of dismissive messages in #platform-redesign channel"},
    {"id": "EV-002", "type": "Email Chain", "date": "2024-03-14", "desc": "Correspondence regarding task reassignment lacking performance justification"},
    {"id": "EV-003", "type": "Calendar Logs", "date": "2024-03-15", "desc": "Records showing complainant excluded from 6 technical architecture meetings"},
    {"id": "EV-004", "type": "HR Log", "date": "2024-03-13", "desc": "Entry HR-LOG-2024-0043 documenting initial informal complaint"},
    {"id": "EV-005", "type": "Performance Review", "date": "2024-03-16", "desc": "2023 Review for complainant: 'Exceeds Expectations' (4.2/5.0)"}
  ],
  "timeline": [
    {"date": "2023-12-04", "event": "Complainant assigned to cross-functional redesign project"},
    {"date": "2024-01-08", "event": "Informal complaint filed with HR regarding dismissive behavior"},
    {"date": "2024-01-15", "event": "First documented dismissive Slack message (EV-001)"},
    {"date": "2024-01-22", "event": "Sprint review incident witnessed by Ishikawa"},
    {"date": "2024-02-08", "event": "Offsite event comments witnessed by Jeffcoat"},
    {"date": "2024-02-12", "event": "Respondent reassigns complainant's tasks to junior engineer"},
    {"date": "2024-03-11", "event": "Formal EEO complaint filed (PSS-EEO-2024-017)"}
  ],
  "findings": [
    {
      "allegation": "Hostile Work Environment",
      "determination": "Substantiated",
      "details": "Pattern of dismissive conduct, public disparagement, and exclusion was severe and pervasive."
    },
    {
      "allegation": "Retaliation",
      "determination": "Substantiated",
      "details": "Adverse action (task reassignment) occurred within 5 weeks of informal complaint without valid justification."
    },
    {
      "allegation": "Discriminatory Conduct",
      "determination": "Partially Substantiated",
      "details": "Differential treatment evident, though specific intent vs interpersonal conflict difficult to isolate."
    }
  ],
  "recommendations": [
    "Mandatory anti-harassment training for respondent (8 hours)",
    "Formal written final warning in respondent's personnel file",
    "Modification of reporting structure to remove dependency",
    "Update to HR informal complaint follow-up procedures"
  ]
}
EOF

# Set ownership
chown ga:ga /home/ga/Documents/case_file.json

# 2. Ensure OpenOffice Writer is running and maximized
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
            echo "OpenOffice window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs (Welcome/Registration)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="