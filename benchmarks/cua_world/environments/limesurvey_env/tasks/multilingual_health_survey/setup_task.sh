#!/bin/bash
echo "=== Setting up Multilingual Health Survey Task ==="

source /workspace/scripts/task_utils.sh

if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# LimeSurvey API readiness is checked inside Python with retries
# Create the English-only vaccine hesitancy survey
python3 << 'PYEOF'
import json, urllib.request, sys, time, subprocess

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=20).read())
    except Exception as e:
        return {"result": None, "error": str(e)}

def db(query):
    result = subprocess.run(
        ["docker", "exec", "limesurvey-db", "mysql",
         "-u", "limesurvey", "-plimesurvey_pass", "limesurvey", "-N", "-e", query],
        capture_output=True, text=True
    )
    return result.stdout.strip()

session = None
for attempt in range(30):  # up to 150 seconds
    resp = api("get_session_key", ["admin", "Admin123!"])
    s = resp.get("result")
    if s and isinstance(s, str) and len(s) > 5 and "error" not in str(s).lower():
        session = s
        print(f"LimeSurvey API ready after attempt {attempt+1}")
        break
    print(f"Waiting for LimeSurvey API... attempt {attempt+1}: {s}")
    time.sleep(5)
if not session:
    print("ERROR: LimeSurvey API not responding after 30 attempts")
    sys.exit(1)

# Remove any existing survey
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if "vaccine" in s.get("surveyls_title", "").lower() or "hesitancy" in s.get("surveyls_title", "").lower():
            api("delete_survey", [session, s["sid"]])
            print(f"Removed existing: {s['surveyls_title']}")
            time.sleep(1)

# Create survey in English ONLY (no Spanish yet - that's the task)
sid = api("add_survey", [session, 0, "Vaccine Acceptance and Hesitancy Study", "en", "G"])["result"]
if not isinstance(sid, int):
    print(f"ERROR creating survey: {sid}")
    sys.exit(1)
print(f"Created survey SID={sid}")

# Set survey description
db(f"""UPDATE lime_surveys_languagesettings
SET surveyls_description='This study examines factors influencing vaccine acceptance and hesitancy among community members. Your responses will help inform public health communication strategies.',
    surveyls_welcometext='Thank you for participating in this important research study.'
WHERE surveyls_survey_id={sid} AND surveyls_language='en'""")

# Create Group 1: Vaccination Experience
gid1 = api("add_group", [session, sid, "Vaccination Experience", ""])["result"]
print(f"Group 1 GID={gid1}")

# Create Group 2: Attitudes and Beliefs
gid2 = api("add_group", [session, sid, "Attitudes and Beliefs", ""])["result"]
print(f"Group 2 GID={gid2}")

# Add questions to Group 1 (Vaccination Experience)
# Q1: Have you received any COVID-19 vaccine? (Radio)
q1 = api("add_question", [session, sid, gid1, "en",
          {"title": "VACC_STATUS", "type": "Y", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q1, int):
    db(f"""UPDATE lime_question_l10ns SET question='Have you received any COVID-19 vaccine?'
    WHERE qid={q1} AND language='en'""")
    print(f"Q1 (VACC_STATUS) QID={q1}")

# Q2: Which vaccines received (Multiple choice short text)
q2 = api("add_question", [session, sid, gid1, "en",
          {"title": "VACC_TYPE", "type": "S", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q2, int):
    db(f"""UPDATE lime_question_l10ns SET question='If vaccinated, which COVID-19 vaccine(s) did you receive? (e.g., Pfizer-BioNTech, Moderna, Johnson and Johnson, AstraZeneca)'
    WHERE qid={q2} AND language='en'""")
    print(f"Q2 (VACC_TYPE) QID={q2}")

# Q3: How easy was access (5-point radio)
q3 = api("add_question", [session, sid, gid1, "en",
          {"title": "ACCESS_EASE", "type": "L", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q3, int):
    db(f"""UPDATE lime_question_l10ns SET question='How easy was it for you to access a COVID-19 vaccine?'
    WHERE qid={q3} AND language='en'""")
    for code, label, order in [("A1","Very easy",1),("A2","Somewhat easy",2),("A3","Neutral",3),("A4","Somewhat difficult",4),("A5","Very difficult",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q3},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q3} AND code='{code}' LIMIT 1""")
    print(f"Q3 (ACCESS_EASE) QID={q3}")

# Q4: Side effects (Yes/No)
q4 = api("add_question", [session, sid, gid1, "en",
          {"title": "SIDE_EFFECTS", "type": "Y", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q4, int):
    db(f"""UPDATE lime_question_l10ns SET question='Did you experience any side effects after receiving the COVID-19 vaccine?'
    WHERE qid={q4} AND language='en'""")
    print(f"Q4 (SIDE_EFFECTS) QID={q4}")

# Add questions to Group 2 (Attitudes and Beliefs)
# Q5: Importance of vaccination (5-point scale)
q5 = api("add_question", [session, sid, gid2, "en",
          {"title": "IMPORTANCE", "type": "L", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q5, int):
    db(f"""UPDATE lime_question_l10ns SET question='How important do you think it is to get vaccinated against COVID-19?'
    WHERE qid={q5} AND language='en'""")
    for code, label, order in [("A1","Extremely important",1),("A2","Very important",2),("A3","Moderately important",3),("A4","Slightly important",4),("A5","Not at all important",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q5},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q5} AND code='{code}' LIMIT 1""")
    print(f"Q5 (IMPORTANCE) QID={q5}")

# Q6: Safety confidence
q6 = api("add_question", [session, sid, gid2, "en",
          {"title": "SAFETY_CONF", "type": "L", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q6, int):
    db(f"""UPDATE lime_question_l10ns SET question='How confident are you that COVID-19 vaccines are safe?'
    WHERE qid={q6} AND language='en'""")
    for code, label, order in [("A1","Very confident",1),("A2","Somewhat confident",2),("A3","Unsure",3),("A4","Not very confident",4),("A5","Not at all confident",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q6},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q6} AND code='{code}' LIMIT 1""")
    print(f"Q6 (SAFETY_CONF) QID={q6}")

# Q7: Effectiveness confidence
q7 = api("add_question", [session, sid, gid2, "en",
          {"title": "EFFECT_CONF", "type": "L", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q7, int):
    db(f"""UPDATE lime_question_l10ns SET question='How confident are you that COVID-19 vaccines are effective?'
    WHERE qid={q7} AND language='en'""")
    for code, label, order in [("A1","Very confident",1),("A2","Somewhat confident",2),("A3","Unsure",3),("A4","Not very confident",4),("A5","Not at all confident",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q7},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q7} AND code='{code}' LIMIT 1""")
    print(f"Q7 (EFFECT_CONF) QID={q7}")

# Q8: Main reason for hesitancy (text)
q8 = api("add_question", [session, sid, gid2, "en",
          {"title": "HESITANCY_REASON", "type": "T", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q8, int):
    db(f"""UPDATE lime_question_l10ns SET question='If you have any concerns or hesitancy about COVID-19 vaccines, please describe your main reason(s):'
    WHERE qid={q8} AND language='en'""")
    print(f"Q8 (HESITANCY_REASON) QID={q8}")

# Save SID
with open("/tmp/multilingual_survey_sid", "w") as f:
    f.write(str(sid))

api("release_session_key", [session])
print(f"English-only vaccine hesitancy survey created SID={sid}")
print("Agent must add Spanish (es) language and translate all questions.")
PYEOF
PYTHON_EXIT=$?
if [ "$PYTHON_EXIT" -ne 0 ]; then
    echo "ERROR: Setup Python script failed (exit code $PYTHON_EXIT)"
    exit 1
fi

SID=$(cat /tmp/multilingual_survey_sid 2>/dev/null || echo "")
echo "$SID" > /tmp/multilingual_survey_sid

# Record baseline: only English should exist
INITIAL_LANG_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID" 2>/dev/null || echo "1")
echo "$INITIAL_LANG_COUNT" > /tmp/multilingual_initial_lang_count

# Record timestamp
date +%s > /tmp/task_start_timestamp

take_screenshot /tmp/task_start_screenshot.png

DISPLAY=:1 wmctrl -a Firefox 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool type --clearmodifiers "http://localhost/index.php/admin" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 3

echo ""
echo "=== Setup Complete ==="
echo "Vaccine Acceptance and Hesitancy Study created (SID=$SID) in English only."
echo "Agent must add Spanish (es) language and translate all 8 questions."
