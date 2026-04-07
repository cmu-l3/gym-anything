#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Training Evaluation Report Task ==="

# Create directories
sudo -u ga mkdir -p /home/ga/Documents/results

# Record task start time
date +%s > /tmp/training_eval_report_start_ts

# Generate the raw, unformatted document
python3 << 'PYEOF'
import os
from docx import Document

doc = Document()

# Add all text as Normal paragraphs with no special formatting
raw_text = [
    "Cybersecurity Awareness Training — Post-Training Evaluation Report",
    "Q4 2024 Training Cohort — Final Report",
    "Meridian Financial Services, Inc.",
    "December 15, 2024",
    "",
    "Executive Summary",
    "",
    "Meridian Financial Services conducted a mandatory 3-day Cybersecurity Awareness Training program for 247 employees across 8 departments during Q4 2024. The program was designed to reduce phishing susceptibility, improve password hygiene, and increase incident reporting rates. Key findings from the evaluation include: Overall participant satisfaction rated 4.3 out of 5.0; Knowledge assessment scores improved by an average of 31 percentage points from pre-test to post-test; Phishing simulation click-through rates decreased by 62% at the 90-day follow-up; The estimated annual cost avoidance from reduced security incidents is $1.2 million; 94% of participants reported the training was directly applicable to their daily work; Manager-reported compliance with security protocols increased from 67% to 91%.",
    "",
    "Program Overview",
    "",
    "The Cybersecurity Awareness Training program was developed in partnership with CyberShield Training Solutions and delivered in cohorts of approximately 30 participants over 8 sessions between October 7 and November 22, 2024. The program utilized a blended learning approach combining instructor-led workshops (60%), hands-on simulation labs (25%), and e-learning modules (15%). Training content was aligned with the NIST Cybersecurity Framework and tailored to financial services industry-specific threats including business email compromise, ransomware, and social engineering attacks.",
    "",
    "Program Objectives",
    "",
    "The program had four primary learning objectives: (1) Identify common phishing tactics and social engineering techniques, (2) Demonstrate proper password management and multi-factor authentication procedures, (3) Apply data classification and handling protocols per company policy, and (4) Execute proper incident reporting procedures within the established 15-minute response window.",
    "",
    "Participant Demographics",
    "",
    "The following table summarizes participant demographics by department:",
    "",
    "Department | Participants | Completion Rate | Avg Tenure (Years)",
    "Retail Banking | 52 | 98% | 4.2",
    "Commercial Lending | 38 | 100% | 6.8",
    "Wealth Management | 29 | 97% | 8.1",
    "Information Technology | 41 | 100% | 5.5",
    "Human Resources | 18 | 100% | 7.3",
    "Operations | 34 | 94% | 3.9",
    "Risk & Compliance | 22 | 100% | 9.2",
    "Customer Service | 13 | 92% | 2.1",
    "Total | 247 | 98% | 5.6",
    "",
    "Level 1: Reaction",
    "",
    "Participant reactions were measured through a post-training survey administered on the final day of each cohort session. The survey used a 5-point Likert scale (1=Strongly Disagree, 5=Strongly Agree) and achieved a 96% response rate (237 of 247 participants).",
    "",
    "Overall Satisfaction Ratings",
    "",
    "Category | Mean Rating (out of 5.0) | Std Dev",
    "Overall program quality | 4.3 | 0.62",
    "Relevance to job role | 4.5 | 0.58",
    "Instructor knowledge and delivery | 4.6 | 0.41",
    "Training materials quality | 4.1 | 0.73",
    "Hands-on lab effectiveness | 4.7 | 0.39",
    "Pace and time allocation | 3.9 | 0.81",
    "Facility and technology | 4.2 | 0.67",
    "",
    "Instructor Effectiveness",
    "",
    "Lead instructor Marcus Chen received consistently high ratings across all cohorts, with particular praise for his use of real-world financial sector breach case studies. Guest instructor Dr. Priya Anand from CyberShield received notable feedback for the hands-on phishing simulation exercises. Participants in Cohorts 6 and 7 noted that the afternoon sessions on Day 2 felt rushed, suggesting a need to extend the data classification module by approximately 30 minutes.",
    "",
    "Open-Ended Feedback Themes",
    "",
    "Analysis of 198 open-ended responses revealed the following recurring themes: the phishing simulation exercises were cited as the most valuable component by 73% of respondents, 45% requested more department-specific examples, 28% suggested adding a module on mobile device security, and 15% felt the pre-training assessment was unnecessarily stressful.",
    "",
    "Level 2: Learning",
    "",
    "Knowledge acquisition was measured through identical pre-test and post-test assessments consisting of 50 multiple-choice questions covering the four learning objectives. Tests were administered on Day 1 (pre) and Day 3 (post).",
    "",
    "Pre-Test vs Post-Test Scores",
    "",
    "Topic | Pre-Test Mean (%) | Post-Test Mean (%) | Gain (pp) | p-value",
    "Phishing Identification | 42 | 78 | 36 | <0.001",
    "Password Management | 55 | 82 | 27 | <0.001",
    "Data Classification | 38 | 71 | 33 | <0.001",
    "Incident Reporting | 47 | 76 | 29 | <0.001",
    "Social Engineering Defense | 33 | 69 | 36 | <0.001",
    "Overall | 43 | 74 | 31 | <0.001",
    "",
    "Learning Objective Achievement",
    "",
    "Based on the post-test results, 89% of participants achieved the mastery threshold of 70% on all four learning objectives. The remaining 11% (27 participants) were enrolled in supplementary e-learning modules and achieved mastery within 2 weeks. The largest knowledge gaps at baseline were found in Social Engineering Defense (33% pre-test mean) and Data Classification (38% pre-test mean), both of which showed the largest absolute gains after training.",
    "",
    "Level 3: Behavior",
    "",
    "Behavioral change was assessed through three mechanisms at the 90-day follow-up point: (1) simulated phishing campaign results, (2) IT security log analysis, and (3) manager assessment surveys.",
    "",
    "Behavior Change Indicators",
    "",
    "Indicator | Baseline (%) | 90-Day Follow-Up (%) | Change (pp)",
    "Phishing email click-through rate | 34 | 13 | -21",
    "Proper incident reporting within 15 min | 23 | 68 | +45",
    "Password policy compliance | 61 | 89 | +28",
    "Multi-factor authentication adoption | 45 | 94 | +49",
    "Clean desk policy adherence | 52 | 78 | +26",
    "Secure file transfer usage | 39 | 83 | +44",
    "",
    "Manager Assessment Summary",
    "",
    "Department managers completed a brief assessment of their direct reports' behavioral changes. Of the 31 managers surveyed, 87% reported noticeable improvement in security-conscious behavior, 74% reported that their teams now consistently follow the incident reporting protocol, and 68% observed improved compliance with data handling procedures.",
    "",
    "Level 4: Results",
    "",
    "Organizational impact was assessed through analysis of security incident data, compliance audit results, and estimated cost metrics for the period September through December 2024.",
    "",
    "ROI Metrics",
    "",
    "Metric | Value | Notes",
    "Training program total cost | $187,500 | Includes vendor fees, materials, facilities, participant time",
    "Security incidents (pre-training quarter) | 23 | Q3 2024",
    "Security incidents (post-training quarter) | 9 | Q4 2024 (partial, annualized)",
    "Estimated annual cost avoidance | $1,200,000 | Based on avg incident cost of $85,700",
    "Compliance audit findings reduced | 67% | From 12 findings to 4",
    "Return on investment (ROI) | 540% | (Benefit - Cost) / Cost",
    "Phishing susceptibility reduction | 62% | Based on simulated campaigns",
    "",
    "Organizational Impact Narrative",
    "",
    "The most significant organizational impact was the 61% reduction in security incidents from Q3 to Q4 2024. While this cannot be attributed solely to the training program (concurrent technical controls were also implemented), the timing and nature of the incident reduction strongly correlate with training completion. The compliance audit conducted in November 2024 showed a 67% reduction in security-related findings compared to the August 2024 audit, with the remaining 4 findings related to legacy system configurations rather than employee behavior.",
    "",
    "Recommendations",
    "",
    "Based on the evaluation findings, the following recommendations are made for the 2025 training program: (1) Extend the data classification module by 30 minutes to address participant feedback about pacing, (2) Develop department-specific case studies for Retail Banking and Customer Service teams who showed lower post-test scores, (3) Add a mobile device security module as requested by 28% of participants, (4) Implement quarterly micro-learning refreshers to maintain knowledge retention, (5) Conduct a 180-day follow-up behavioral assessment to evaluate long-term impact, and (6) Expand the program to include contractor and temporary staff populations.",
    "",
    "Appendix A: Survey Instrument Summary",
    "",
    "The post-training evaluation survey consisted of 3 sections: Section 1 contained 7 Likert-scale items measuring satisfaction and relevance (reported in Level 1), Section 2 contained 3 open-ended questions about most/least valuable components and suggestions for improvement, and Section 3 collected demographic information for subgroup analysis. The survey was administered electronically via SurveyMonkey and took an average of 8 minutes to complete. All responses were anonymous to encourage candid feedback."
]

for text in raw_text:
    doc.add_paragraph(text)

output_path = "/home/ga/Documents/training_eval_raw.docx"
doc.save(output_path)
os.chown(output_path, 1000, 1000)  # ga:ga
PYEOF

sudo chmod 644 /home/ga/Documents/training_eval_raw.docx

# Launch WPS Writer
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/training_eval_raw.docx &"

# Wait for window to appear
wait_for_window "WPS Writer\|training_eval_raw" 30

# Maximize and focus
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any EULA/startup dialogs
dismiss_wps_dialogs

# Ensure focus is back on the document
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/training_eval_report_initial.png

echo "=== Task Setup Complete ==="