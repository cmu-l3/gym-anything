#!/bin/bash
echo "=== Setting up Token Participant Management Task ==="

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
# Create the pre-built 360 feedback survey using the LimeSurvey API + direct DB
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=20).read())
    except Exception as e:
        return {"result": None, "error": str(e)}

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

# Remove any existing survey with this title
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if "leadership competency" in s.get("surveyls_title", "").lower():
            api("delete_survey", [session, s["sid"]])
            print(f"Removed existing survey: {s['surveyls_title']}")
            time.sleep(1)

# Create the survey (NOT active, no tokens yet)
sid = api("add_survey", [session, 0, "Leadership Competency Assessment 360", "en", "G"])["result"]
if not isinstance(sid, int):
    print(f"ERROR: Could not create survey: {sid}")
    sys.exit(1)
print(f"Created survey SID={sid}")

# Add question group
gid = api("add_group", [session, sid, "Leadership Behaviors", ""])["result"]
if not isinstance(gid, int):
    print(f"ERROR: Could not create group: {gid}")
    sys.exit(1)
print(f"Created group GID={gid}")

# Add the Array question (10 leadership competency items from Korn Ferry framework)
q_data = {
    "title": "LCOMP",
    "type": "F",
    "mandatory": "Y",
    "other": "N",
    "relevance": "1",
    "question_order": 1,
    "scale_id": 0
}
q_l10ns = {
    "en": {
        "question": "Please rate this leader on each of the following competencies.",
        "help": "Use the 5-point scale: 1=Significantly Below Expectations, 2=Below Expectations, 3=Meets Expectations, 4=Exceeds Expectations, 5=Significantly Exceeds Expectations"
    }
}
qid = api("add_question", [session, sid, gid, "en", q_data, [], [], []])
print(f"Add question result: {qid}")
qid = qid.get("result")

if not isinstance(qid, int):
    # Try simpler form
    q_data2 = {"title": "LCOMP", "type": "F", "mandatory": "Y"}
    qid = api("add_question", [session, sid, gid, "en", q_data2, [], [], []])["result"]
    print(f"Retry add question result: {qid}")

# Add sub-questions via direct DB if API succeeds
import subprocess

if isinstance(qid, int):
    print(f"Created array question QID={qid}")
    # Leadership competency sub-questions (Korn Ferry/Lominger framework)
    subquestions = [
        ("SQ001", "Makes timely decisions when facing uncertainty or incomplete information"),
        ("SQ002", "Clearly communicates expectations and strategic priorities to the team"),
        ("SQ003", "Provides meaningful developmental feedback and coaching to direct reports"),
        ("SQ004", "Builds trust by consistently following through on commitments"),
        ("SQ005", "Resolves interpersonal conflict constructively and with fairness"),
        ("SQ006", "Demonstrates strategic perspective when making day-to-day decisions"),
        ("SQ007", "Creates an environment that motivates and energizes team members"),
        ("SQ008", "Takes accountability for team outcomes — both successes and setbacks"),
        ("SQ009", "Actively promotes diverse perspectives and inclusive team practices"),
        ("SQ010", "Drives continuous process improvement and organizational learning"),
    ]

    for i, (code, text) in enumerate(subquestions):
        sq_data = {"title": code, "type": "F", "mandatory": "N"}
        sq_l10ns = {"en": {"question": text}}
        sq_result = api("add_question", [session, sid, gid, "en",
                                          {"title": code, "type": "T", "mandatory": "N",
                                           "parent_qid": qid, "scale_id": 0},
                                          [], [], []])
        print(f"  Sub-question {code}: {sq_result.get('result')}")

    # Add answer options (5-point scale)
    answers = [
        ("A1", "1 - Significantly Below Expectations", 1),
        ("A2", "2 - Below Expectations", 2),
        ("A3", "3 - Meets Expectations", 3),
        ("A4", "4 - Exceeds Expectations", 4),
        ("A5", "5 - Significantly Exceeds Expectations", 5),
    ]
    for code, text, sortorder in answers:
        ans_result = api("set_question_properties", [session, qid, {"answers": []}])
        # Use direct DB for answers
        cmd = f"""docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -e "
INSERT IGNORE INTO lime_answers (qid, code, sortorder, assessment_value, scale_id)
VALUES ({qid}, '{code}', {sortorder}, {sortorder}, 0);
INSERT IGNORE INTO lime_answer_l10ns (aid, language, answer)
SELECT id, 'en', '{text}' FROM lime_answers WHERE qid={qid} AND code='{code}' LIMIT 1;
" 2>/dev/null"""
        subprocess.run(cmd, shell=True)

print(f"Survey setup complete: SID={sid}")
# Save SID for later
with open("/tmp/token_survey_sid", "w") as f:
    f.write(str(sid))

api("release_session_key", [session])
PYEOF
PYTHON_EXIT=$?
if [ "$PYTHON_EXIT" -ne 0 ]; then
    echo "ERROR: Setup Python script failed (exit code $PYTHON_EXIT)"
    exit 1
fi

# Record baseline
SID=$(cat /tmp/token_survey_sid 2>/dev/null || echo "")
echo "$SID" > /tmp/token_survey_sid_baseline

# Record token table state (should NOT exist yet since tokens not enabled)
TOKEN_TABLE_EXISTS="false"
if [ -n "$SID" ]; then
    TABLE_CHECK=$(limesurvey_query "SHOW TABLES LIKE 'lime_tokens_${SID}'" 2>/dev/null || echo "")
    [ -n "$TABLE_CHECK" ] && TOKEN_TABLE_EXISTS="true"
fi
echo "$TOKEN_TABLE_EXISTS" > /tmp/token_initial_state

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
echo "Survey 'Leadership Competency Assessment 360' created (SID=$SID)"
echo "Tokens are NOT enabled. Agent must enable tokens, add 4 participants, customize email."
