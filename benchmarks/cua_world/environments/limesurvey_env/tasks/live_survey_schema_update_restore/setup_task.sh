#!/bin/bash
set -e
echo "=== Setting up Live Survey Update Task ==="

source /workspace/scripts/task_utils.sh

# Fallback query function
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# 1. Wait for LimeSurvey API
echo "Waiting for LimeSurvey API..."
python3 << 'PYEOF'
import json, urllib.request, time, sys
BASE = "http://localhost/index.php/admin/remotecontrol"
def api(method, params):
    try:
        data = json.dumps({"method": method, "params": params, "id": 1}).encode()
        req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
        return json.loads(urllib.request.urlopen(req, timeout=10).read())
    except: return {}

for i in range(30):
    res = api("get_session_key", ["admin", "Admin123!"])
    if "result" in res and res["result"]:
        print("API Ready")
        sys.exit(0)
    time.sleep(2)
print("API Timeout")
sys.exit(1)
PYEOF

# 2. Create the Survey Structure via Python Script
echo "Creating survey and seeding data..."
python3 << 'PYEOF'
import json, urllib.request, random, datetime

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req).read())

# Login
key = api("get_session_key", ["admin", "Admin123!"])["result"]

# 1. Create Survey
sid = api("add_survey", [key, 0, "2024 Employee Voice", "en", "G"])["result"]
print(f"SURVEY_ID={sid}")

# 2. Add Groups
g_demo = api("add_group", [key, sid, "Demographics", "Employee information"])["result"]
g_feed = api("add_group", [key, sid, "Feedback", "General feedback"])["result"]

# 3. Add Questions (INTENTIONALLY MISSING 'Department')
# Q1: Years of Service (Numerical)
api("add_question", [key, sid, g_demo, "en", {"title": "tenure", "type": "N", "mandatory": "Y", "question": "Years of service:"}, [], [], []])

# Q2: Satisfaction (List 5 point)
api("add_question", [key, sid, g_feed, "en", {"title": "satisfaction", "type": "5", "mandatory": "Y", "question": "Overall satisfaction:"}, [], [], []])

# Q3: Comments (Long Text)
api("add_question", [key, sid, g_feed, "en", {"title": "comments", "type": "T", "mandatory": "N", "question": "Any other comments?"}, [], [], []])

# 4. Activate Survey
api("activate_survey", [key, sid])
print("Survey activated")

# Write SID to file for bash
with open("/tmp/task_sid", "w") as f:
    f.write(str(sid))
PYEOF

SID=$(cat /tmp/task_sid)

# 3. Seed 15 Responses directly via SQL (to simulate pre-existing data)
# We use SQL because API 'add_response' is slower/complex for batch and we want specific timestamps
echo "Seeding 15 responses into lime_survey_${SID}..."

# Generate SQL insert statements
# Using a specific known comment for verification: "The flexible hours are the best part of working here"
cat > /tmp/seed_data.sql << SQLEOF
INSERT INTO lime_survey_${SID} (submitdate, lastpage, startlanguage, seed, tenure, satisfaction, comments) VALUES
('2023-10-01 09:00:00', 2, 'en', '1001', 2, '4', 'The flexible hours are the best part of working here'),
('2023-10-01 09:15:00', 2, 'en', '1002', 5, '5', 'Great team atmosphere'),
('2023-10-01 10:30:00', 2, 'en', '1003', 1, '3', 'Onboarding was a bit messy'),
('2023-10-02 08:45:00', 2, 'en', '1004', 10, '5', 'Love it here'),
('2023-10-02 11:20:00', 2, 'en', '1005', 3, '2', 'Need better coffee'),
('2023-10-03 14:00:00', 2, 'en', '1006', 7, '4', 'Management is supportive'),
('2023-10-03 15:10:00', 2, 'en', '1007', 4, '4', 'Good benefits'),
('2023-10-04 09:30:00', 2, 'en', '1008', 2, '1', 'Salaries are below market'),
('2023-10-04 10:00:00', 2, 'en', '1009', 6, '3', 'Okay but could be better'),
('2023-10-05 13:45:00', 2, 'en', '1010', 8, '5', 'Proud to work here'),
('2023-10-05 16:20:00', 2, 'en', '1011', 1, '4', 'Learning a lot'),
('2023-10-06 09:05:00', 2, 'en', '1012', 3, '3', 'Middle management issues'),
('2023-10-06 11:15:00', 2, 'en', '1013', 5, '5', 'Best job I ever had'),
('2023-10-07 10:00:00', 2, 'en', '1014', 9, '2', 'Too much bureaucracy'),
('2023-10-07 14:30:00', 2, 'en', '1015', 2, '4', 'Happy overall');
SQLEOF

limesurvey_query "$(cat /tmp/seed_data.sql)"

# 4. Record Initial State
INITIAL_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_survey_${SID}")
echo "Initial response count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
date +%s > /tmp/task_start_time.txt

# 5. UI Setup
echo "Launching Firefox..."
focus_firefox
# Navigate to survey summary page
DISPLAY=:1 xdotool type "http://localhost/index.php/admin/survey/sa/view/surveyid/${SID}"
DISPLAY=:1 xdotool key Return
sleep 5

# 6. Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Survey ID: $SID"
echo "Responses Seeded: $INITIAL_COUNT"