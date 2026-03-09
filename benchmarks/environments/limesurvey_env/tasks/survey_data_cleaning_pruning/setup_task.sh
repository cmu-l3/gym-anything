#!/bin/bash
set -e
echo "=== Setting up Survey Data Cleaning Task ==="

source /workspace/scripts/task_utils.sh

# Install python dependencies for setup script if needed
# (Env usually has them, but safety check)
pip3 install mysql-connector-python requests > /dev/null 2>&1 || true

# Python script to setup the survey and inject dirty data
python3 - << 'EOF'
import sys
import json
import time
import urllib.request
import mysql.connector

# Configuration
API_URL = "http://localhost/index.php/admin/remotecontrol"
ADMIN_USER = "admin"
ADMIN_PASS = "Admin123!"
SURVEY_TITLE = "Product Concept Test 2025"

# DB Config
DB_CONFIG = {
    'user': 'limesurvey',
    'password': 'limesurvey_pass',
    'host': 'limesurvey-db',
    'database': 'limesurvey',
    'raise_on_warnings': True
}

def api_req(method, params, req_id=1):
    payload = {
        "method": method,
        "params": params,
        "id": req_id
    }
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(API_URL, data=data, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        print(f"API Error: {e}")
        return None

def wait_for_api():
    for _ in range(20):
        res = api_req("get_session_key", [ADMIN_USER, ADMIN_PASS])
        if res and "result" in res and res["result"]:
            return res["result"]
        time.sleep(2)
    return None

def setup():
    print("Connecting to LimeSurvey API...")
    skey = wait_for_api()
    if not skey:
        print("Failed to get session key")
        sys.exit(1)

    # 1. Cleanup existing survey
    print("Cleaning up old surveys...")
    surveys = api_req("list_surveys", [skey])
    if surveys and "result" in surveys and isinstance(surveys["result"], list):
        for s in surveys["result"]:
            if s["surveyls_title"] == SURVEY_TITLE:
                api_req("delete_survey", [skey, s["sid"]])
                print(f"Deleted old survey {s['sid']}")

    # 2. Create Survey
    print("Creating new survey...")
    res = api_req("add_survey", [skey, 0, SURVEY_TITLE, "en", "G"])
    sid = res["result"]
    print(f"Created survey SID: {sid}")

    # 3. Create Group
    res = api_req("add_group", [skey, sid, "Demographics", ""])
    gid = res["result"]

    # 4. Create Questions
    # Q1: Name (Free text)
    q_name_data = {"title": "fname", "type": "S", "mandatory": "N", "question": "First Name"}
    res = api_req("add_question", [skey, sid, gid, "en", q_name_data, [], [], []])
    qid_name = res["result"]

    # Q2: Email (Free text)
    q_email_data = {"title": "email", "type": "S", "mandatory": "N", "question": "Email Address"}
    res = api_req("add_question", [skey, sid, gid, "en", q_email_data, [], [], []])
    qid_email = res["result"]

    # 5. Activate Survey
    print("Activating survey...")
    res = api_req("activate_survey", [skey, sid])
    if "error" in res and res["error"]:
        print(f"Activation failed: {res['error']}")
        sys.exit(1)

    api_req("release_session_key", [skey])

    # 6. Inject Data via MySQL
    # We need to find the column names. LimeSurvey names them {sid}X{gid}X{qid}
    col_name = f"{sid}X{gid}X{qid_name}"
    col_email = f"{sid}X{gid}X{qid_email}"
    table_name = f"lime_survey_{sid}"

    print(f"Injecting data into {table_name}...")
    
    # Dataset: (Name, Email, Is_Complete)
    # Is_Complete=True -> submitdate=NOW(), False -> submitdate=NULL
    data_points = [
        ("Jane Doe", "jane.doe88@gmail.com", True),       # GOOD
        ("Marcus Smith", "m.smith@outlook.com", True),    # GOOD
        ("TEST", "admin@company.com", True),              # BAD (Name=TEST)
        ("John Doe", "john.d@example.com", True),         # BAD (Email=@example.com)
        ("Sarah Jones", "s.jones@gmail.com", False),      # BAD (Incomplete)
        ("Li Wei", "li.wei.biz@yahoo.com", True),         # GOOD
        ("Tester", "test@test.com", False),               # BAD (Incomplete)
        ("Auto Bot", "bot@example.com", True)             # BAD (Email=@example.com)
    ]

    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()

        for name, email, complete in data_points:
            submit_val = "NOW()" if complete else "NULL"
            # Using direct string formatting for column names (safe here as they are integers from API)
            # Using parameters for values
            sql = f"""
                INSERT INTO {table_name} 
                (submitdate, lastpage, startlanguage, `{col_name}`, `{col_email}`, startdate)
                VALUES ({submit_val}, 1, 'en', %s, %s, NOW())
            """
            cursor.execute(sql, (name, email))
        
        conn.commit()
        print("Data injection complete.")
        
        # Save SID for export script
        with open("/tmp/task_sid.txt", "w") as f:
            f.write(str(sid))

    except mysql.connector.Error as err:
        print(f"Database Error: {err}")
        sys.exit(1)
    finally:
        if 'conn' in locals() and conn.is_connected():
            cursor.close()
            conn.close()

if __name__ == "__main__":
    setup()
EOF

# Record initial counts for later reference (optional, but good for debugging)
SID=$(cat /tmp/task_sid.txt)
echo "Survey ID: $SID"

# Snapshot
take_screenshot /tmp/task_initial.png

# Setup Firefox
echo "Launching Firefox..."
focus_firefox
DISPLAY=:1 xdotool type "http://localhost/index.php/admin/responses/sa/browse/surveyid/$SID"
DISPLAY=:1 xdotool key Return
sleep 5

echo "=== Setup Complete ==="