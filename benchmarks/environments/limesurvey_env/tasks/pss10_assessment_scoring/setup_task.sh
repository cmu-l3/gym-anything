#!/bin/bash
set -e

echo "=== Setting up PSS-10 Assessment Scoring Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey API to be ready
echo "Waiting for LimeSurvey API..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin/remotecontrol > /dev/null; then
        echo "API Endpoint reachable"
        break
    fi
    sleep 2
done

# Create the PSS-10 survey using Python and JSON-RPC
# We create it with INCORRECT configuration for the agent to fix
python3 - << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"
USER = "admin"
PASS = "Admin123!"

def rpc(method, params, req_id=1):
    payload = json.dumps({"method": method, "params": params, "id": req_id}).encode()
    req = urllib.request.Request(BASE, data=payload, headers={"Content-Type": "application/json"})
    try:
        response = urllib.request.urlopen(req, timeout=10)
        return json.loads(response.read())
    except Exception as e:
        return {"error": str(e)}

# Get Session Key
print("Getting session key...")
res = rpc("get_session_key", [USER, PASS])
key = res.get("result")
if not key or "error" in str(key):
    print(f"Failed to get session key: {res}")
    sys.exit(1)

# Clean up any existing PSS-10 surveys
print("Cleaning old surveys...")
surveys = rpc("list_surveys", [key]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if "PSS-10" in s.get("surveyls_title", ""):
            rpc("delete_survey", [key, s["sid"]])

# Create Survey
print("Creating PSS-10 Survey...")
sid = rpc("add_survey", [key, 0, "Perceived Stress Scale (PSS-10) - Student Well-Being Study", "en"])["result"]
print(f"Created Survey SID: {sid}")

# Create Group
gid = rpc("add_group", [key, sid, "Stress Perception Items"])["result"]

# PSS-10 Items
# 0-4 scale: Never, Almost Never, Sometimes, Fairly Often, Very Often
answers = [
    {"code": "0", "answer": "Never", "assessment_value": 0},
    {"code": "1", "answer": "Almost Never", "assessment_value": 1},
    {"code": "2", "answer": "Sometimes", "assessment_value": 2},
    {"code": "3", "answer": "Fairly Often", "assessment_value": 3},
    {"code": "4", "answer": "Very Often", "assessment_value": 4}
]

questions = [
    ("PSS01", "In the last month, how often have you been upset because of something that happened unexpectedly?"),
    ("PSS02", "In the last month, how often have you felt that you were unable to control the important things in your life?"),
    ("PSS03", "In the last month, how often have you felt nervous and stressed?"),
    ("PSS04", "In the last month, how often have you felt confident about your ability to handle your personal problems?"), # Reverse
    ("PSS05", "In the last month, how often have you felt that things were going your way?"), # Reverse
    ("PSS06", "In the last month, how often have you found that you could not cope with all the things that you had to do?"),
    ("PSS07", "In the last month, how often have you been able to control irritations in your life?"), # Reverse
    ("PSS08", "In the last month, how often have you felt that you were on top of things?"), # Reverse
    ("PSS09", "In the last month, how often have you been angered because of things that were outside of your control?"),
    ("PSS10", "In the last month, how often have you felt difficulties were piling up so high that you could not overcome them?")
]

# Add questions and answers
for code, text in questions:
    q_data = {"title": code, "type": "L", "mandatory": "Y"} # List (Radio)
    qid = rpc("add_question", [key, sid, gid, "en", q_data])["result"]
    
    # Add answers with DEFAULT (Forward) scoring for ALL items
    # The agent's task is to fix this for PSS04, 05, 07, 08
    for ans in answers:
        # Note: API might not fully support setting assessment_value directly in add_question in older versions,
        # but we will fix values via SQL below to be sure.
        rpc("add_answer", [key, sid, qid, ans["code"], ans["answer"]])

rpc("release_session_key", [key])
print("Survey creation complete.")
PYEOF

# Get the SID of the newly created survey
SURVEY_ID=$(limesurvey_query "SELECT sid FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%PSS-10%' ORDER BY surveyls_survey_id DESC LIMIT 1")
echo "Survey ID: $SURVEY_ID"
echo "$SURVEY_ID" > /tmp/pss10_sid.txt

# CRITICAL SETUP: Manually set the DB state to ensure starting conditions
# 1. Assessments disabled
limesurvey_query "UPDATE lime_surveys SET assessments='N', active='N' WHERE sid=$SURVEY_ID"

# 2. Set ALL assessment values to forward scoring (0,1,2,3,4) matches codes (0,1,2,3,4)
# This mimics the "default" state where someone just typed them in without adjusting for reverse items.
limesurvey_query "UPDATE lime_answers a JOIN lime_questions q ON a.qid=q.qid SET a.assessment_value=CAST(a.code AS UNSIGNED) WHERE q.sid=$SURVEY_ID"

# Verify initial state via screenshot
focus_firefox
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="