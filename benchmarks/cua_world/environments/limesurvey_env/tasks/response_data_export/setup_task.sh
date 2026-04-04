#!/bin/bash
set -e

echo "=== Setting up Response Data Export Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Downloads directory exists and is empty of target files
mkdir -p /home/ga/Downloads
rm -f /home/ga/Downloads/q3_customer_experience_responses.csv
rm -f /home/ga/Downloads/q3_customer_experience_structure.lss
chown -R ga:ga /home/ga/Downloads

# Wait for LimeSurvey API
wait_for_limesurvey_api() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if curl -s "http://localhost/index.php/admin/remotecontrol" | grep -q "JsonRPC"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}
wait_for_limesurvey_api || echo "WARNING: API might not be fully ready, proceeding anyway..."

# Create Survey Population Script
# This python script creates the survey structure and populates it with 25 realistic responses
cat > /tmp/populate_survey.py << 'PYEOF'
import json
import urllib.request
import sys
import random
import time
from datetime import datetime, timedelta

URL = "http://localhost/index.php/admin/remotecontrol"
USER = "admin"
PASSWORD = "Admin123!"

def rpc(method, *params):
    payload = {
        "method": method,
        "params": params,
        "id": 1
    }
    req = urllib.request.Request(
        URL, 
        data=json.dumps(payload).encode(),
        headers={'content-type': 'application/json'}
    )
    response = urllib.request.urlopen(req)
    return json.loads(response.read())

def get_session_key():
    res = rpc("get_session_key", USER, PASSWORD)
    if "result" in res and res["result"]:
        return res["result"]
    raise Exception(f"Failed to get session key: {res}")

def main():
    try:
        key = get_session_key()
    except Exception as e:
        print(f"Error getting key: {e}")
        return

    # 1. Check if survey exists and delete it to ensure clean state
    surveys = rpc("list_surveys", key, USER)
    if surveys.get("result"):
        for s in surveys["result"]:
            if s["surveyls_title"] == "Q3 2024 Retail Customer Experience Survey":
                print(f"Deleting existing survey {s['sid']}...")
                rpc("delete_survey", key, s['sid'])

    # 2. Create Survey
    print("Creating survey...")
    res = rpc("add_survey", key, 0, "Q3 2024 Retail Customer Experience Survey", "en", "G")
    sid = res["result"]
    print(f"Survey ID: {sid}")

    # 3. Add Groups
    print("Adding groups...")
    g1 = rpc("add_group", key, sid, "Satisfaction & Loyalty")["result"]
    g2 = rpc("add_group", key, sid, "Demographics & Feedback")["result"]

    # 4. Add Questions
    print("Adding questions...")
    
    # Q1: Satisfaction (5 point radio)
    # Using 'L' (List Radio)
    q1_data = {"title": "Q01", "type": "L", "mandatory": "Y"}
    q1 = rpc("add_question", key, sid, g1, "en", q1_data, [], [], [])["result"]
    rpc("set_question_properties", key, q1, {"question": "Overall, how satisfied are you with your most recent shopping experience?"})
    
    # Add answers for Q1
    answers_q1 = [
        ("A1", "Very Dissatisfied"), ("A2", "Dissatisfied"), ("A3", "Neutral"), 
        ("A4", "Satisfied"), ("A5", "Very Satisfied")
    ]
    for code, text in answers_q1:
        rpc("add_answer", key, q1, code, "en", text)

    # Q2: NPS (0-10) - Using Numerical Input 'N' for simplicity in API, or List Radio.
    # Let's use List Radio 'L' to simulate NPS scale properly with 11 options
    q2_data = {"title": "Q02", "type": "L", "mandatory": "N"}
    q2 = rpc("add_question", key, sid, g1, "en", q2_data, [], [], [])["result"]
    rpc("set_question_properties", key, q2, {"question": "How likely are you to recommend our store to a friend or colleague? (0-10)"})
    for i in range(11):
        rpc("add_answer", key, q2, str(i), "en", str(i))

    # Q3: Departments (Multiple Choice 'M')
    q3_data = {"title": "Q03", "type": "M", "mandatory": "N"}
    q3 = rpc("add_question", key, sid, g1, "en", q3_data, [], [], [])["result"]
    rpc("set_question_properties", key, q3, {"question": "Which departments did you visit?"})
    
    depts = [
        ("D1", "Produce"), ("D2", "Bakery"), ("D3", "Deli"), ("D4", "Dairy"),
        ("D5", "Frozen Foods"), ("D6", "Household"), ("D7", "Electronics"), ("D8", "Clothing")
    ]
    for code, text in depts:
        rpc("add_answer", key, q3, code, "en", text)

    # Q4: Age (List Radio 'L')
    q4_data = {"title": "Q04", "type": "L", "mandatory": "Y"}
    q4 = rpc("add_question", key, sid, g2, "en", q4_data, [], [], [])["result"]
    rpc("set_question_properties", key, q4, {"question": "What is your age group?"})
    
    ages = [("1", "18-24"), ("2", "25-34"), ("3", "35-44"), ("4", "45-54"), ("5", "55-64"), ("6", "65+")]
    for code, text in ages:
        rpc("add_answer", key, q4, code, "en", text)

    # Q5: Feedback (Long Text 'T')
    q5_data = {"title": "Q05", "type": "T", "mandatory": "N"}
    q5 = rpc("add_question", key, sid, g2, "en", q5_data, [], [], [])["result"]
    rpc("set_question_properties", key, q5, {"question": "What is one thing we could do to improve your experience?"})

    # 5. Activate Survey
    print("Activating survey...")
    rpc("activate_survey", key, sid)

    # 6. Add Responses (25 realistic responses)
    print("Generating 25 responses...")
    
    comments = [
        "Checkout lines were too long.", "Great organic selection!", "Staff was helpful.", 
        "Prices are high.", "Clean store.", "Love the bakery.", "Parking is terrible.",
        "Need more vegan options.", "Self-checkout broken.", "Excellent service at deli.",
        "Out of stock on milk.", "Very satisfied.", "Music was too loud.", "Bathrooms were clean.",
        "Best store in town.", "Vegetables were not fresh.", "Friendly cashiers.",
        "Hard to find items.", "Good weekly deals.", "Please open earlier.",
        "Carts need repair.", "Fast service.", "Love the new layout.", "Too cold inside.", "Okay experience."
    ]

    for i in range(25):
        # Skew satisfaction towards positive (A4, A5)
        sat = random.choice(["A1", "A2", "A3", "A4", "A4", "A4", "A5", "A5", "A5", "A5"])
        
        # NPS correlated with satisfaction
        if sat in ["A4", "A5"]:
            nps = str(random.randint(7, 10))
        elif sat == "A3":
            nps = str(random.randint(5, 7))
        else:
            nps = str(random.randint(0, 4))
            
        # Random departments
        visited = []
        for d_code, _ in depts:
            if random.random() > 0.6:
                visited.append(d_code)
        if not visited: visited.append("D1")
        
        age = random.choice([x[0] for x in ages])
        comment = comments[i]
        
        # Build response data
        # Note: keys must match column names in DB usually, or Question Codes
        resp_data = {
            "Q01": sat,
            "Q02": nps,
            "Q04": age,
            "Q05": comment
        }
        # For multiple choice Q3, format is typically Q3_Code = "Y"
        for d in visited:
            resp_data[f"Q03_{d}"] = "Y"

        rpc("add_response", key, sid, resp_data)

    print("Survey setup complete.")
    rpc("release_session_key", key)

if __name__ == "__main__":
    main()
PYEOF

# Run the population script
python3 /tmp/populate_survey.py

# Launch Firefox focused on LimeSurvey Admin
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    
    # Wait for Firefox
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
            break
        fi
        sleep 1
    done
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="