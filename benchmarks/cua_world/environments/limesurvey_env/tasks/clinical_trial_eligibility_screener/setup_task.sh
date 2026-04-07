#!/bin/bash
echo "=== Setting up Clinical Trial Eligibility Screener Task ==="

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

# Delete stale output files BEFORE recording timestamp
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/cvr_survey_sid 2>/dev/null || true
rm -f /tmp/cvr_baseline.json 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the CVR-2025 survey using API for survey/groups, SQL for questions
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
    r = subprocess.run(
        ["docker", "exec", "limesurvey-db", "mysql",
         "-u", "limesurvey", "-plimesurvey_pass", "limesurvey", "-N", "-e", query],
        capture_output=True, text=True
    )
    return r.stdout.strip()

# Wait for API
session = None
for attempt in range(30):
    resp = api("get_session_key", ["admin", "Admin123!"])
    s = resp.get("result")
    if s and isinstance(s, str) and len(s) > 5 and "error" not in str(s).lower():
        session = s
        print(f"LimeSurvey API ready after attempt {attempt+1}")
        break
    print(f"Waiting for LimeSurvey API... attempt {attempt+1}: {s}")
    time.sleep(5)
if not session:
    print("ERROR: LimeSurvey API not responding")
    sys.exit(1)

# Remove any existing CVR surveys
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        title = s.get("surveyls_title", "").lower()
        if "cardiovascular" in title or "cvr-2025" in title:
            api("delete_survey", [session, s["sid"]])
            print(f"Removed existing: {s['surveyls_title']}")
            time.sleep(1)

# Create survey via API
sid = api("add_survey", [session, 0, "Cardiovascular Risk Trial Screening (Protocol CVR-2025)", "en", "G"])["result"]
if not isinstance(sid, int):
    print(f"ERROR creating survey: {sid}")
    sys.exit(1)
print(f"Created survey SID={sid}")

# Set description
db(f"""UPDATE lime_surveys_languagesettings
SET surveyls_description='A multi-center clinical trial screening instrument for cardiovascular risk assessment. Protocol CVR-2025.',
    surveyls_welcometext='Welcome to the Cardiovascular Risk Trial Screening. Please answer all questions accurately.'
WHERE surveyls_survey_id={sid} AND surveyls_language='en'""")

# Create groups via API
gid1 = api("add_group", [session, sid, "Demographics", ""])["result"]
gid2 = api("add_group", [session, sid, "Medical History", ""])["result"]
print(f"Demographics GID={gid1}, Medical History GID={gid2}")

# ========== CREATE QUESTIONS VIA SQL ==========
# (add_question API returns HTTP 500 in this LimeSurvey version)

# Q1: DOB (Date)
db(f"INSERT INTO lime_questions (sid,gid,type,title,question_order,mandatory,relevance,scale_id,parent_qid) VALUES ({sid},{gid1},'D','DOB',1,'Y','1',0,0)")
q_dob = db(f"SELECT qid FROM lime_questions WHERE sid={sid} AND title='DOB' AND parent_qid=0")
db(f"INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({q_dob},'en','What is your date of birth?')")
print(f"DOB QID={q_dob}")

# Q2: SEX (List/Radio)
db(f"INSERT INTO lime_questions (sid,gid,type,title,question_order,mandatory,relevance,scale_id,parent_qid) VALUES ({sid},{gid1},'L','SEX',2,'Y','1',0,0)")
q_sex = db(f"SELECT qid FROM lime_questions WHERE sid={sid} AND title='SEX' AND parent_qid=0")
db(f"INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({q_sex},'en','What is your biological sex?')")
# Answer options (code max 5 chars)
for code, label, order in [("M", "Male", 1), ("F", "Female", 2)]:
    db(f"INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q_sex},'{code}',{order},0,0)")
    db(f"INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT aid,'en','{label}' FROM lime_answers WHERE qid={q_sex} AND code='{code}' LIMIT 1")
print(f"SEX QID={q_sex}")

# Q3: HEIGHT_CM (Numerical, no validation — agent must add)
db(f"INSERT INTO lime_questions (sid,gid,type,title,question_order,mandatory,relevance,scale_id,parent_qid) VALUES ({sid},{gid1},'N','HEIGHT_CM',3,'Y','1',0,0)")
q_height = db(f"SELECT qid FROM lime_questions WHERE sid={sid} AND title='HEIGHT_CM' AND parent_qid=0")
db(f"INSERT INTO lime_question_l10ns (qid,language,question,help) VALUES ({q_height},'en','What is your height in centimeters?','Enter your height in centimeters (e.g., 175)')")
print(f"HEIGHT_CM QID={q_height}")

# Q4: WEIGHT_KG (Numerical, no validation — agent must add)
db(f"INSERT INTO lime_questions (sid,gid,type,title,question_order,mandatory,relevance,scale_id,parent_qid) VALUES ({sid},{gid1},'N','WEIGHT_KG',4,'Y','1',0,0)")
q_weight = db(f"SELECT qid FROM lime_questions WHERE sid={sid} AND title='WEIGHT_KG' AND parent_qid=0")
db(f"INSERT INTO lime_question_l10ns (qid,language,question,help) VALUES ({q_weight},'en','What is your weight in kilograms?','Enter your weight in kilograms (e.g., 70)')")
print(f"WEIGHT_KG QID={q_weight}")

# Q5: DIABETES (Yes/No)
db(f"INSERT INTO lime_questions (sid,gid,type,title,question_order,mandatory,relevance,scale_id,parent_qid) VALUES ({sid},{gid2},'Y','DIABETES',1,'Y','1',0,0)")
q_diabetes = db(f"SELECT qid FROM lime_questions WHERE sid={sid} AND title='DIABETES' AND parent_qid=0")
db(f"INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({q_diabetes},'en','Have you been diagnosed with diabetes (Type 1 or Type 2)?')")
print(f"DIABETES QID={q_diabetes}")

# Q6: HEART_COND (Yes/No)
db(f"INSERT INTO lime_questions (sid,gid,type,title,question_order,mandatory,relevance,scale_id,parent_qid) VALUES ({sid},{gid2},'Y','HEART_COND',2,'Y','1',0,0)")
q_heart = db(f"SELECT qid FROM lime_questions WHERE sid={sid} AND title='HEART_COND' AND parent_qid=0")
db(f"INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({q_heart},'en','Do you have any diagnosed heart conditions?')")
print(f"HEART_COND QID={q_heart}")

# Q7: CURRENT_MEDS (Multiple Choice with 5 sub-questions)
db(f"INSERT INTO lime_questions (sid,gid,type,title,question_order,mandatory,relevance,scale_id,parent_qid) VALUES ({sid},{gid2},'M','CURRENT_MEDS',3,'Y','1',0,0)")
q_meds = db(f"SELECT qid FROM lime_questions WHERE sid={sid} AND title='CURRENT_MEDS' AND parent_qid=0")
db(f"INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({q_meds},'en','Which medications are you currently taking? (Select all that apply)')")
meds = [
    ("SQ001", "ACE Inhibitors"),
    ("SQ002", "Beta Blockers"),
    ("SQ003", "Statins"),
    ("SQ004", "Blood Thinners"),
    ("SQ005", "None of the above")
]
for i, (code, label) in enumerate(meds):
    db(f"INSERT INTO lime_questions (parent_qid,sid,gid,type,title,question_order,mandatory,relevance,scale_id) VALUES ({q_meds},{sid},{gid2},'M','{code}',{i+1},'N','1',0)")
    sq = db(f"SELECT qid FROM lime_questions WHERE parent_qid={q_meds} AND title='{code}'")
    if sq:
        db(f"INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({sq},'en','{label}')")
print(f"CURRENT_MEDS QID={q_meds}")

# Q8: ALLERGIES (Short Text)
db(f"INSERT INTO lime_questions (sid,gid,type,title,question_order,mandatory,relevance,scale_id,parent_qid) VALUES ({sid},{gid2},'S','ALLERGIES',4,'N','1',0,0)")
q_allergies = db(f"SELECT qid FROM lime_questions WHERE sid={sid} AND title='ALLERGIES' AND parent_qid=0")
db(f"INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({q_allergies},'en','List any known drug allergies (leave blank if none)')")
print(f"ALLERGIES QID={q_allergies}")

# Save SID
with open("/tmp/cvr_survey_sid", "w") as f:
    f.write(str(sid))
baseline = {"sid": sid, "sex_qid": int(q_sex) if q_sex else None}
with open("/tmp/cvr_baseline.json", "w") as f:
    json.dump(baseline, f)

api("release_session_key", [session])
print(f"\nCVR-2025 survey created: SID={sid}")
print("Agent must configure: validation, equations, conditional groups, assessment, quotas, activation.")
PYEOF
PYTHON_EXIT=$?
if [ "$PYTHON_EXIT" -ne 0 ]; then
    echo "ERROR: Setup Python script failed (exit code $PYTHON_EXIT)"
    exit 1
fi

SID=$(cat /tmp/cvr_survey_sid 2>/dev/null || echo "")
echo "Survey SID=$SID"

# Navigate Firefox to the survey
restart_firefox "http://localhost/index.php/admin/survey/sa/view/surveyid/$SID"

take_screenshot /tmp/task_initial.png

echo ""
echo "=== Setup Complete ==="
