#!/bin/bash
echo "=== Setting up Expression Manager Conditions Task ==="

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
# Create the conference feedback survey (WITHOUT conditions - that's the task)
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
        title = s.get("surveyls_title", "").lower()
        if "tech summit" in title or "attendee feedback" in title and "annual" in title:
            api("delete_survey", [session, s["sid"]])
            print(f"Removed: {s['surveyls_title']}")
            time.sleep(1)

# Create the conference feedback survey
sid = api("add_survey", [session, 0, "Annual Tech Summit 2024 \u2014 Attendee Feedback", "en", "G"])["result"]
if not isinstance(sid, int):
    print(f"ERROR creating survey: {sid}")
    sys.exit(1)
print(f"Created survey SID={sid}")

# Description
db(f"""UPDATE lime_surveys_languagesettings
SET surveyls_description='We value your feedback from the Annual Tech Summit 2024. Your responses will help us improve future events.',
    surveyls_welcometext='Thank you for attending the Annual Tech Summit 2024. This survey takes approximately 5 minutes to complete.'
WHERE surveyls_survey_id={sid} AND surveyls_language='en'""")

# NO end URL yet - that's part of the task

# Group 1: Overall Conference Experience
gid1 = api("add_group", [session, sid, "Overall Conference Experience", ""])["result"]
print(f"Group 1 GID={gid1}")

# Group 2: Session Feedback (should be conditional - agent must add condition)
gid2 = api("add_group", [session, sid, "Session Feedback", ""])["result"]
print(f"Group 2 GID={gid2}")

# Group 3: Future Event Planning
gid3 = api("add_group", [session, sid, "Future Event Planning", ""])["result"]
print(f"Group 3 GID={gid3}")

# --- Group 1 Questions ---
# Q1: Overall satisfaction rating (1-10 numerical)
q_rating = api("add_question", [session, sid, gid1, "en",
               {"title": "OVERALL_RATING", "type": "N", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q_rating, int):
    db(f"""UPDATE lime_question_l10ns SET question='On a scale of 1 to 10, how would you rate your overall experience at the Annual Tech Summit 2024? (1=Very poor, 10=Excellent)'
    WHERE qid={q_rating} AND language='en'""")
    # Set numeric range via attributes
    db(f"""INSERT IGNORE INTO lime_question_attributes (qid,value,attribute) VALUES ({q_rating},'1','min_num_value')""")
    db(f"""INSERT IGNORE INTO lime_question_attributes (qid,value,attribute) VALUES ({q_rating},'10','max_num_value')""")
    print(f"OVERALL_RATING QID={q_rating}")

# Q2: Would you recommend (Yes/No)
q_recommend = api("add_question", [session, sid, gid1, "en",
                  {"title": "RECOMMEND", "type": "Y", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q_recommend, int):
    db(f"""UPDATE lime_question_l10ns SET question='Would you recommend the Annual Tech Summit to a colleague or peer?'
    WHERE qid={q_recommend} AND language='en'""")
    print(f"RECOMMEND QID={q_recommend}")

# Q3: Improvement suggestions (long text - should be conditional on rating <=6)
q_improve = api("add_question", [session, sid, gid1, "en",
                {"title": "IMPROVE_COMMENTS", "type": "T", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q_improve, int):
    db(f"""UPDATE lime_question_l10ns SET question='What specific improvements would you suggest for future Tech Summit events?'
    WHERE qid={q_improve} AND language='en'""")
    # NO condition set yet - that's the task
    print(f"IMPROVE_COMMENTS QID={q_improve}")

# Q4: Attended breakout sessions (Yes/No) - key for Group 2 condition
q_attended = api("add_question", [session, sid, gid1, "en",
                 {"title": "ATTENDED_SESSIONS", "type": "Y", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q_attended, int):
    db(f"""UPDATE lime_question_l10ns SET question='Did you attend any breakout sessions or workshops during the Tech Summit?'
    WHERE qid={q_attended} AND language='en'""")
    print(f"ATTENDED_SESSIONS QID={q_attended}")

# --- Group 2 Questions: Session Feedback (currently unconditional - agent must add condition to group) ---
# Q5: Session quality array
q_session_qual = api("add_question", [session, sid, gid2, "en",
                     {"title": "SESSION_QUALITY", "type": "F", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q_session_qual, int):
    db(f"""UPDATE lime_question_l10ns SET question='Please rate the quality of the breakout sessions you attended:'
    WHERE qid={q_session_qual} AND language='en'""")
    for code, label, order in [("A1","1 - Poor",1),("A2","2 - Below average",2),("A3","3 - Average",3),("A4","4 - Good",4),("A5","5 - Excellent",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q_session_qual},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q_session_qual} AND code='{code}' LIMIT 1""")
    sessions = [("SQ001","AI and Machine Learning Applications"),("SQ002","Cloud Infrastructure and DevOps"),("SQ003","Cybersecurity Trends"),("SQ004","Product Management Masterclass"),("SQ005","Leadership in Tech")]
    for i, (code, label) in enumerate(sessions):
        db(f"""INSERT INTO lime_questions (parent_qid,sid,gid,type,title,question_order,mandatory,relevance,scale_id) VALUES ({q_session_qual},{sid},{gid2},'F','{code}',{i+1},'N','1',0)""")
        new_qid = db(f"SELECT qid FROM lime_questions WHERE parent_qid={q_session_qual} AND title='{code}'")
        if new_qid:
            db(f"""INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({new_qid},'en','{label}')""")
    print(f"SESSION_QUALITY QID={q_session_qual}")

# Q6: Most valuable session (text)
q_best_session = api("add_question", [session, sid, gid2, "en",
                     {"title": "BEST_SESSION", "type": "S", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q_best_session, int):
    db(f"""UPDATE lime_question_l10ns SET question='Which breakout session did you find most valuable, and why?'
    WHERE qid={q_best_session} AND language='en'""")
    print(f"BEST_SESSION QID={q_best_session}")

# --- Group 3 Questions: Future Event Planning ---
# Q7: Likelihood to attend next year (radio)
q_return = api("add_question", [session, sid, gid3, "en",
               {"title": "RETURN_INTENT", "type": "L", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q_return, int):
    db(f"""UPDATE lime_question_l10ns SET question='How likely are you to attend the Annual Tech Summit next year?'
    WHERE qid={q_return} AND language='en'""")
    for code, label, order in [("A1","Definitely will attend",1),("A2","Probably will attend",2),("A3","Unsure",3),("A4","Probably will not attend",4),("A5","Definitely will not attend",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q_return},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q_return} AND code='{code}' LIMIT 1""")
    print(f"RETURN_INTENT QID={q_return}")

# Q8: Topic interests for next year (multiple choice)
q_topics = api("add_question", [session, sid, gid3, "en",
               {"title": "FUTURE_TOPICS", "type": "M", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q_topics, int):
    db(f"""UPDATE lime_question_l10ns SET question='Which topics would you most like to see covered at the next Tech Summit? (Select all that apply)'
    WHERE qid={q_topics} AND language='en'""")
    topics = [("SQ001","Generative AI and Large Language Models"),("SQ002","Quantum Computing"),("SQ003","Sustainability and Green Tech"),("SQ004","Web3 and Decentralized Systems"),("SQ005","Data Privacy and Regulation"),("SQ006","Mental Health in the Tech Workplace")]
    for i, (code, label) in enumerate(topics):
        db(f"""INSERT INTO lime_questions (parent_qid,sid,gid,type,title,question_order,mandatory,relevance,scale_id) VALUES ({q_topics},{sid},{gid3},'M','{code}',{i+1},'N','1',0)""")
        new_qid = db(f"SELECT qid FROM lime_questions WHERE parent_qid={q_topics} AND title='{code}'")
        if new_qid:
            db(f"""INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({new_qid},'en','{label}')""")
    print(f"FUTURE_TOPICS QID={q_topics}")

# Save SID and key question IDs
info = {
    "sid": sid,
    "gid_session_feedback": gid2,
    "qid_overall_rating": q_rating,
    "qid_improve_comments": q_improve,
    "qid_attended_sessions": q_attended
}
with open("/tmp/expr_survey_info.json", "w") as f:
    json.dump(info, f)
with open("/tmp/expr_survey_sid", "w") as f:
    f.write(str(sid))

api("release_session_key", [session])
print(f"\nConference feedback survey created: SID={sid}")
print("NO conditions set yet — agent must add expression manager conditions and end URL.")
PYEOF
PYTHON_EXIT=$?
if [ "$PYTHON_EXIT" -ne 0 ]; then
    echo "ERROR: Setup Python script failed (exit code $PYTHON_EXIT)"
    exit 1
fi

SID=$(cat /tmp/expr_survey_sid 2>/dev/null || echo "")

# Record baseline: no conditions, no end URL
INITIAL_CONDITION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND relevance IS NOT NULL AND relevance != '1' AND relevance != '' AND parent_qid=0" 2>/dev/null || echo "0")
echo "$INITIAL_CONDITION_COUNT" > /tmp/expr_initial_conditions

INITIAL_GROUP_CONDITION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID AND grelevance IS NOT NULL AND grelevance != '1' AND grelevance != ''" 2>/dev/null || echo "0")
echo "$INITIAL_GROUP_CONDITION_COUNT" > /tmp/expr_initial_group_conditions

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
echo "Conference feedback survey created (SID=$SID) with 8 questions, NO conditions."
echo "Agent must:"
echo "1. Set group condition on 'Session Feedback' group (only show if ATTENDED_SESSIONS=Y)"
echo "2. Set question condition on IMPROVE_COMMENTS (only show if OVERALL_RATING<=6)"
echo "3. Set end redirect URL to http://techsummit.example.com/thank-you"
