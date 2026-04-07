#!/bin/bash
# Do NOT use set -e
echo "=== Setting up quarterly_student_progress_report task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing outputs
rm -f /home/ga/Documents/class_analysis.py 2>/dev/null || true
rm -f /home/ga/Documents/class_dashboard.html 2>/dev/null || true
rm -f /home/ga/Documents/progress_report.odt 2>/dev/null || true

# Record task start timestamp (anti-gaming)
date +%s > /tmp/quarterly_progress_start_ts
chmod 666 /tmp/quarterly_progress_start_ts

# Generate deterministic student performance dataset
# 25 students x 5 subjects x 4 quarters = 500 rows
# Uses only deterministic formulas (no random) for full reproducibility
echo "Generating student performance dataset..."
python3 << 'PYEOF'
import csv

students = [
    {"id": 1,  "name": "Carlos Mendoza",   "type": "decline",         "base": 80, "rate": 5, "att": 88, "study": 6},
    {"id": 2,  "name": "Amara Diallo",     "type": "stable",          "base": 82, "rate": 0, "att": 92, "study": 12},
    {"id": 3,  "name": "Fatima Al-Rashid",  "type": "low_att",         "base": 79, "rate": 0, "att": 68, "study": 10},
    {"id": 4,  "name": "Wei Chen",          "type": "stable",          "base": 85, "rate": 0, "att": 95, "study": 14},
    {"id": 5,  "name": "Yuki Tanaka",       "type": "decline",         "base": 78, "rate": 4, "att": 90, "study": 5},
    {"id": 6,  "name": "Sofia Herrera",     "type": "improving",       "base": 68, "rate": 3, "att": 91, "study": 16},
    {"id": 7,  "name": "Kwame Asante",      "type": "stable",          "base": 76, "rate": 0, "att": 89, "study": 11},
    {"id": 8,  "name": "Elena Popov",       "type": "stable",          "base": 83, "rate": 0, "att": 94, "study": 13},
    {"id": 9,  "name": "Priya Sharma",      "type": "decline",         "base": 76, "rate": 6, "att": 87, "study": 4},
    {"id": 10, "name": "Liam O'Brien",      "type": "decline_low_att", "base": 77, "rate": 4, "att": 72, "study": 7},
    {"id": 11, "name": "Aisha Mohammed",    "type": "stable",          "base": 80, "rate": 0, "att": 93, "study": 12},
    {"id": 12, "name": "Mateo Silva",       "type": "improving",       "base": 65, "rate": 4, "att": 90, "study": 15},
    {"id": 13, "name": "Hana Kim",          "type": "stable",          "base": 88, "rate": 0, "att": 96, "study": 14},
    {"id": 14, "name": "Diego Ramirez",     "type": "stable",          "base": 74, "rate": 0, "att": 88, "study": 9},
    {"id": 15, "name": "Zara Okafor",       "type": "improving",       "base": 70, "rate": 3, "att": 92, "study": 17},
    {"id": 16, "name": "Ivan Petrov",       "type": "stable",          "base": 79, "rate": 0, "att": 91, "study": 10},
    {"id": 17, "name": "Maya Patel",        "type": "stable",          "base": 81, "rate": 0, "att": 93, "study": 13},
    {"id": 18, "name": "Lucas Martin",      "type": "stable",          "base": 77, "rate": 0, "att": 90, "study": 11},
    {"id": 19, "name": "Nia Williams",      "type": "improving",       "base": 66, "rate": 4, "att": 89, "study": 16},
    {"id": 20, "name": "Omar Hassan",       "type": "stable",          "base": 78, "rate": 0, "att": 91, "study": 10},
    {"id": 21, "name": "Sakura Ito",        "type": "stable",          "base": 84, "rate": 0, "att": 95, "study": 13},
    {"id": 22, "name": "Felix Schmidt",     "type": "stable",          "base": 75, "rate": 0, "att": 88, "study": 8},
    {"id": 23, "name": "Adaeze Nwosu",      "type": "improving",       "base": 69, "rate": 3, "att": 93, "study": 15},
    {"id": 24, "name": "Tomas Novak",       "type": "stable",          "base": 80, "rate": 0, "att": 92, "study": 12},
    {"id": 25, "name": "Isabela Costa",     "type": "stable",          "base": 82, "rate": 0, "att": 94, "study": 14},
]

subjects = ["Math", "Science", "English", "History", "Art"]
quarters = ["Q1", "Q2", "Q3", "Q4"]
subj_offset = {"Math": 2, "Science": -1, "English": 3, "History": -3, "Art": 1}

with open("/home/ga/Documents/class_records.csv", "w", newline="") as f:
    w = csv.writer(f, delimiter=";")
    w.writerow(["StudentID", "Name", "Subject", "Quarter", "Score", "Attendance", "StudyHoursWeekly"])

    for s in students:
        sid = s["id"]
        for si, subj in enumerate(subjects):
            for qi, q in enumerate(quarters):
                # Deterministic per-cell noise (no random module)
                noise = (sid * 7 + si * 13 + qi * 11) % 5 - 2  # range [-2, +2]

                # Score based on archetype
                base = s["base"] + subj_offset[subj] + noise
                if s["type"] in ("decline", "decline_low_att"):
                    score = base - qi * s["rate"]
                elif s["type"] == "improving":
                    score = base + qi * s["rate"]
                else:
                    score = base
                score = max(40, min(98, score))

                # Attendance based on archetype
                att_noise = (sid * 3 + qi * 5 + si * 7) % 5 - 2  # range [-2, +2]
                if s["type"] in ("low_att", "decline_low_att"):
                    att_noise = (sid * 3 + qi * 5 + si * 7) % 7 - 3  # range [-3, +3]
                att = round(s["att"] + att_noise, 1)

                # StudyHoursWeekly with occasional NA
                if (sid * 7 + qi * 3 + si * 11) % 23 == 0:
                    study_str = "NA"
                else:
                    study_str = str(s["study"])

                w.writerow([sid, s["name"], subj, q, score, att, study_str])

print("Generated class_records.csv with 500 rows")
PYEOF

chown ga:ga /home/ga/Documents/class_records.csv
chmod 644 /home/ga/Documents/class_records.csv

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Verify Sugar session is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Launch Sugar Terminal Activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 10

# Verify Terminal is running
if pgrep -f "Terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/quarterly_progress_start.png" 2>/dev/null || true

echo "=== quarterly_student_progress_report task setup complete ==="
echo "Dataset placed at /home/ga/Documents/class_records.csv"
echo "Agent must analyze data, create HTML dashboard, and write progress report in Sugar Write."
