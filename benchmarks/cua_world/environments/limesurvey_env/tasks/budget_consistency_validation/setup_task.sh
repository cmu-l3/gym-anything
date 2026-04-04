#!/bin/bash
set -e
echo "=== Setting up Budget Consistency Validation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the survey structure using Python and JSON-RPC API
# This ensures a clean, known starting state
echo "Creating survey structure..."
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=10).read())
    except Exception as e:
        return {"result": None, "error": str(e)}

# Get session key
session = None
for attempt in range(10):
    resp = api("get_session_key", ["admin", "Admin123!"])
    s = resp.get("result")
    if s and isinstance(s, str) and len(s) > 5 and "error" not in str(s).lower():
        session = s
        break
    time.sleep(2)

if not session:
    print("Failed to get session key")
    sys.exit(1)

# Clean up existing survey if it exists
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if s.get("surveyls_title") == "Household Financial Wellness 2025":
            api("delete_survey", [session, s["sid"]])
            print(f"Deleted existing survey {s['sid']}")

# Create Survey
sid = api("add_survey", [session, 0, "Household Financial Wellness 2025", "en", "G"])["result"]
print(f"Created survey SID: {sid}")

# Create Group
gid = api("add_group", [session, sid, "Financials", "Monthly income and expense details"])["result"]
print(f"Created group GID: {gid}")

# Create Q_INCOME (Numerical Input)
q_income_data = {
    "title": "Q_INCOME",
    "type": "N", # Numerical input
    "mandatory": "Y",
    "question_order": 0
}
q_income_l10n = {"en": {"question": "What is your total monthly net income?", "help": "Enter numeric value only"}}
qid_income = api("add_question", [session, sid, gid, "en", q_income_data, q_income_l10n])["result"]
print(f"Created Q_INCOME QID: {qid_income}")

# Create Q_EXPENSES (Multiple Numerical Input)
# In LimeSurvey, Multiple Numerical Input is type 'K'
q_expense_data = {
    "title": "Q_EXPENSES",
    "type": "K", 
    "mandatory": "Y",
    "question_order": 1
}
q_expense_l10n = {"en": {"question": "Please break down your monthly expenses."}}
qid_expense = api("add_question", [session, sid, gid, "en", q_expense_data, q_expense_l10n])["result"]
print(f"Created Q_EXPENSES QID: {qid_expense}")

# Add Subquestions for Q_EXPENSES
subquestions = [
    ("SQ001", "Rent or Mortgage"),
    ("SQ002", "Food and Groceries"),
    ("SQ003", "Utilities (Gas, Electric, Water)"),
    ("SQ004", "Healthcare"),
    ("SQ005", "Transportation")
]

for code, text in subquestions:
    # API add_subquestion parameters: session_key, question_id, code, l10n_data
    # Note: add_subquestion signature might vary by version, using add_question approach often works for subqs if supported, 
    # but strictly 'add_subquestion' is safer if available. 
    # Fallback: DB insertion is often used in these scripts, but let's try a standard loop.
    # The LS API is tricky; let's use direct DB injection for subquestions if API is complex, 
    # but `add_question` with `parent_qid` is the standard LS 6.x way if add_subquestion isn't exposed perfectly.
    # Actually, for type K, subquestions are just questions with parent_qid.
    
    # We will let the bash script handle subquestions via direct DB if this is too complex,
    # but let's try to be clean.
    pass

api("release_session_key", [session])
PYEOF

# Add subquestions via Database (Reliable fallback for specific question structures)
# Get the SID and QID_EXPENSE
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title='Household Financial Wellness 2025' LIMIT 1")
QID_EXPENSE=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='Q_EXPENSES' AND parent_qid=0")

if [ -n "$QID_EXPENSE" ]; then
    echo "Adding subquestions to QID $QID_EXPENSE..."
    # Insert subquestions directly
    limesurvey_query "INSERT INTO lime_questions (sid, gid, type, title, question, parent_qid, question_order, language) VALUES 
    ($SID, (SELECT gid FROM lime_questions WHERE qid=$QID_EXPENSE), 'T', 'SQ001', 'Rent or Mortgage', $QID_EXPENSE, 1, 'en'),
    ($SID, (SELECT gid FROM lime_questions WHERE qid=$QID_EXPENSE), 'T', 'SQ002', 'Food and Groceries', $QID_EXPENSE, 2, 'en'),
    ($SID, (SELECT gid FROM lime_questions WHERE qid=$QID_EXPENSE), 'T', 'SQ003', 'Utilities', $QID_EXPENSE, 3, 'en'),
    ($SID, (SELECT gid FROM lime_questions WHERE qid=$QID_EXPENSE), 'T', 'SQ004', 'Healthcare', $QID_EXPENSE, 4, 'en'),
    ($SID, (SELECT gid FROM lime_questions WHERE qid=$QID_EXPENSE), 'T', 'SQ005', 'Transportation', $QID_EXPENSE, 5, 'en');"
    
    # Also need l10n entries for them to show up properly with text
    # (The query above puts text in 'question' column which is legacy, standard requires lime_question_l10ns)
    # We will do proper l10n inserts
    for i in {1..5}; do
        SQ_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE parent_qid=$QID_EXPENSE AND title='SQ00$i'")
        TEXT="Expense Category $i"
        case $i in
            1) TEXT="Rent or Mortgage" ;;
            2) TEXT="Food and Groceries" ;;
            3) TEXT="Utilities" ;;
            4) TEXT="Healthcare" ;;
            5) TEXT="Transportation" ;;
        esac
        limesurvey_query "INSERT INTO lime_question_l10ns (qid, question, language) VALUES ($SQ_QID, '$TEXT', 'en') ON DUPLICATE KEY UPDATE question='$TEXT'"
    done
fi

# Ensure Firefox is running
echo "Launching Firefox..."
focus_firefox
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="