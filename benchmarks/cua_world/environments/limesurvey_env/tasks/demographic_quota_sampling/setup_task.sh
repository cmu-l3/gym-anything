#!/bin/bash
echo "=== Setting up Demographic Quota Sampling Task ==="

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
# Create the consumer electronics survey (without quotas - that's the task)
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
        if "consumer electronics" in title or "electronics preferences" in title:
            api("delete_survey", [session, s["sid"]])
            print(f"Removed existing: {s['surveyls_title']}")
            time.sleep(1)

# Create survey
sid = api("add_survey", [session, 0, "Consumer Electronics Preferences Study 2024", "en", "G"])["result"]
if not isinstance(sid, int):
    print(f"ERROR creating survey: {sid}")
    sys.exit(1)
print(f"Created survey SID={sid}")

# Set survey description
db(f"""UPDATE lime_surveys_languagesettings
SET surveyls_description='This survey examines consumer electronics purchase behavior and preferences. Results will inform product development and marketing strategies.',
    surveyls_welcometext='Thank you for participating in the Consumer Electronics Preferences Study 2024.'
WHERE surveyls_survey_id={sid} AND surveyls_language='en'""")

# Create Group 1: Demographics (MUST come first to enable quota linkage)
gid1 = api("add_group", [session, sid, "Respondent Profile", ""])["result"]
print(f"Group 1 GID={gid1}")

# Create Group 2: Purchase Behavior
gid2 = api("add_group", [session, sid, "Purchase Behavior", ""])["result"]
print(f"Group 2 GID={gid2}")

# Create Group 3: Product Preferences
gid3 = api("add_group", [session, sid, "Product Preferences", ""])["result"]
print(f"Group 3 GID={gid3}")

# --- Group 1: Demographics ---
# Q1: GENDER (Radio) - key quota question
q_gender = api("add_question", [session, sid, gid1, "en",
               {"title": "GENDER", "type": "L", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q_gender, int):
    db(f"""UPDATE lime_question_l10ns SET question='What is your gender?'
    WHERE qid={q_gender} AND language='en'""")
    for code, label, order in [("Male","Male",1),("Female","Female",2),("NonBinary","Non-binary / Gender non-conforming",3),("Other","Prefer to self-describe",4),("NoAnswer","Prefer not to answer",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q_gender},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q_gender} AND code='{code}' LIMIT 1""")
    print(f"GENDER question QID={q_gender}")
else:
    print(f"Warning: GENDER question creation returned: {q_gender}")
    q_gender = None

# Q2: AGE_RANGE (Radio) - key quota question
q_age = api("add_question", [session, sid, gid1, "en",
            {"title": "AGE_RANGE", "type": "L", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q_age, int):
    db(f"""UPDATE lime_question_l10ns SET question='What is your age range?'
    WHERE qid={q_age} AND language='en'""")
    for code, label, order in [("U18","Under 18",1),("18-34","18-34",2),("35-54","35-54",3),("55plus","55 or older",4)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q_age},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q_age} AND code='{code}' LIMIT 1""")
    print(f"AGE_RANGE question QID={q_age}")
else:
    print(f"Warning: AGE_RANGE question creation returned: {q_age}")
    q_age = None

# Q3: Country (Radio, simplified)
q_country = api("add_question", [session, sid, gid1, "en",
                {"title": "COUNTRY", "type": "L", "mandatory": "Y"}, [], [], []])["result"]
if isinstance(q_country, int):
    db(f"""UPDATE lime_question_l10ns SET question='What country do you currently reside in?'
    WHERE qid={q_country} AND language='en'""")
    for code, label, order in [("US","United States",1),("CA","Canada",2),("UK","United Kingdom",3),("AU","Australia",4),("Other","Other",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q_country},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q_country} AND code='{code}' LIMIT 1""")

# --- Group 2: Purchase Behavior ---
# Q4: Categories purchased (Multiple choice)
q_cats = api("add_question", [session, sid, gid2, "en",
             {"title": "CATEGORIES", "type": "M", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q_cats, int):
    db(f"""UPDATE lime_question_l10ns SET question='Which of the following consumer electronics categories have you purchased in the last 12 months? (Select all that apply)'
    WHERE qid={q_cats} AND language='en'""")
    categories = [("SQ001","Smartphones / Mobile phones"),("SQ002","Laptops / Tablets"),("SQ003","Smart TVs / Streaming devices"),("SQ004","Headphones / Earbuds"),("SQ005","Smart home devices (speakers, doorbells, thermostats)"),("SQ006","Gaming consoles / accessories"),("SQ007","Cameras / Photography equipment"),("SQ008","Wearables / Smartwatches")]
    for code, label in categories:
        db(f"""INSERT INTO lime_questions (parent_qid,sid,gid,type,title,question_order,mandatory,relevance,scale_id) VALUES ({q_cats},{sid},{gid2},'M','{code}',{categories.index((code,label))+1},'N','1',0)""")
        new_qid = db(f"SELECT qid FROM lime_questions WHERE parent_qid={q_cats} AND title='{code}'")
        if new_qid:
            db(f"""INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({new_qid},'en','{label}')""")

# Q5: Annual spend (Radio)
q_spend = api("add_question", [session, sid, gid2, "en",
              {"title": "ANNUAL_SPEND", "type": "L", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q_spend, int):
    db(f"""UPDATE lime_question_l10ns SET question='Approximately how much did you spend on consumer electronics in the last 12 months?'
    WHERE qid={q_spend} AND language='en'""")
    for code, label, order in [("A1","Less than $250",1),("A2","$250-$499",2),("A3","$500-$999",3),("A4","$1,000-$2,499",4),("A5","$2,500 or more",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q_spend},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q_spend} AND code='{code}' LIMIT 1""")

# --- Group 3: Product Preferences ---
# Q6: Ranking of purchase factors
q_rank = api("add_question", [session, sid, gid3, "en",
             {"title": "PURCHASE_FACTORS", "type": "R", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q_rank, int):
    db(f"""UPDATE lime_question_l10ns SET question='Please rank the following factors in order of importance when purchasing consumer electronics (1=Most important):'
    WHERE qid={q_rank} AND language='en'""")
    factors = [("SQ001","Price / Value for money"),("SQ002","Brand reputation"),("SQ003","Technical specifications / Performance"),("SQ004","Design / Aesthetics"),("SQ005","Ecosystem compatibility (works with your other devices)"),("SQ006","User reviews and ratings")]
    for i, (code, label) in enumerate(factors):
        db(f"""INSERT INTO lime_questions (parent_qid,sid,gid,type,title,question_order,mandatory,relevance,scale_id) VALUES ({q_rank},{sid},{gid3},'R','{code}',{i+1},'N','1',0)""")
        new_qid = db(f"SELECT qid FROM lime_questions WHERE parent_qid={q_rank} AND title='{code}'")
        if new_qid:
            db(f"""INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({new_qid},'en','{label}')""")

# Q7: Brand preference (Array)
q_brands = api("add_question", [session, sid, gid3, "en",
               {"title": "BRAND_PREF", "type": "F", "mandatory": "N"}, [], [], []])["result"]
if isinstance(q_brands, int):
    db(f"""UPDATE lime_question_l10ns SET question='For each product category, rate your preference for the following brands:'
    WHERE qid={q_brands} AND language='en'""")
    for code, label, order in [("A1","1 - Strongly dislike",1),("A2","2 - Dislike",2),("A3","3 - Neutral",3),("A4","4 - Like",4),("A5","5 - Strongly like",5)]:
        db(f"""INSERT INTO lime_answers (qid,code,sortorder,assessment_value,scale_id) VALUES ({q_brands},'{code}',{order},{order},0)""")
        db(f"""INSERT INTO lime_answer_l10ns (aid,language,answer) SELECT id,'en','{label}' FROM lime_answers WHERE qid={q_brands} AND code='{code}' LIMIT 1""")
    brands_sq = [("SQ001","Apple"),("SQ002","Samsung"),("SQ003","Sony"),("SQ004","LG"),("SQ005","Microsoft")]
    for i, (code, label) in enumerate(brands_sq):
        db(f"""INSERT INTO lime_questions (parent_qid,sid,gid,type,title,question_order,mandatory,relevance,scale_id) VALUES ({q_brands},{sid},{gid3},'F','{code}',{i+1},'N','1',0)""")
        new_qid = db(f"SELECT qid FROM lime_questions WHERE parent_qid={q_brands} AND title='{code}'")
        if new_qid:
            db(f"""INSERT INTO lime_question_l10ns (qid,language,question) VALUES ({new_qid},'en','{label}')""")

# Save key QIDs for export verification
with open("/tmp/quota_survey_sid", "w") as f:
    f.write(str(sid))
info = {"sid": sid, "gender_qid": q_gender, "age_qid": q_age}
with open("/tmp/quota_survey_info.json", "w") as f:
    json.dump(info, f)

api("release_session_key", [session])
print(f"\nConsumer electronics survey created: SID={sid}")
print(f"GENDER QID={q_gender}, AGE_RANGE QID={q_age}")
print("NO QUOTAS created yet — agent must configure 4 quotas.")
PYEOF
PYTHON_EXIT=$?
if [ "$PYTHON_EXIT" -ne 0 ]; then
    echo "ERROR: Setup Python script failed (exit code $PYTHON_EXIT)"
    exit 1
fi

SID=$(cat /tmp/quota_survey_sid 2>/dev/null || echo "")

# Record initial quota count (should be 0)
INITIAL_QUOTA_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_quota WHERE sid=$SID" 2>/dev/null || echo "0")
INITIAL_QUOTA_COUNT=${INITIAL_QUOTA_COUNT:-0}
echo "$INITIAL_QUOTA_COUNT" > /tmp/quota_initial_count
echo "Initial quota count: $INITIAL_QUOTA_COUNT (should be 0)"

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
echo "Survey SID=$SID created with GENDER and AGE_RANGE questions."
echo "Agent must configure 4 quotas (Young Male, Young Female, Mid-Age Male, Mid-Age Female), each limiting to 25 responses."
