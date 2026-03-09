#!/bin/bash
set -e
echo "=== Setting up Task: Broken Logic Troubleshooting ==="

source /workspace/scripts/task_utils.sh

# Define specific SID to ensure we know where to look
SID=78901

# Wait for MySQL to be ready
wait_for_mysql() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec limesurvey-db mysqladmin ping -h localhost -u root -plimesurvey_root_pw 2>/dev/null; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

if ! wait_for_mysql; then
    echo "Error: MySQL not ready"
    exit 1
fi

# Clean up any existing survey with this SID
limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SID"
limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID"
limesurvey_query "DELETE FROM lime_groups WHERE sid=$SID"
limesurvey_query "DELETE FROM lime_questions WHERE sid=$SID"
limesurvey_query "DELETE FROM lime_answers WHERE qid IN (SELECT qid FROM lime_questions WHERE sid=$SID)"

echo "Creating survey structure with BROKEN logic..."

# 1. Create Survey
limesurvey_query "INSERT INTO lime_surveys (sid, owner_id, active, format, language, datecreated) VALUES ($SID, 1, 'N', 'G', 'en', NOW())"
limesurvey_query "INSERT INTO lime_surveys_languagesettings (surveyls_survey_id, surveyls_language, surveyls_title, surveyls_description) VALUES ($SID, 'en', 'Annual Employee Climate Monitor 2025', 'Internal survey for HR assessment. DEBUGGING REQUIRED.')"

# 2. Create Groups
# GID 100: Demographics
# GID 101: Remote Work Tools (ERROR 1: relevance uses 'work_style' instead of 'work_mode')
limesurvey_query "INSERT INTO lime_groups (gid, sid, group_name, group_order, relevance) VALUES (100, $SID, 'Demographics', 0, '1')"
# Note: Inserting raw string with quotes requires careful escaping in bash
limesurvey_query "INSERT INTO lime_groups (gid, sid, group_name, group_order, relevance) VALUES (101, $SID, 'Remote Work Tools', 1, 'work_style.NAOK == \"Hybrid\" OR work_style.NAOK == \"Remote\"')"

# 3. Create Questions
# QID 1001: work_mode (L) - The correct variable source
# QID 1002: dep_code (S) - Source for other logic
# QID 1003: Q_Sales (T) - ERROR 2: Unclosed quote
# QID 1004: Q_Shift (T) - ERROR 3: Single equals sign
# QID 1005: Q_NetSpeed (N) - Inside the broken group

# Q1: work_mode
limesurvey_query "INSERT INTO lime_questions (qid, parent_qid, sid, gid, type, title, question, mandatory, question_order) VALUES (1001, 0, $SID, 100, 'L', 'work_mode', 'What is your primary work arrangement?', 'Y', 1)"

# Q2: dep_code
limesurvey_query "INSERT INTO lime_questions (qid, parent_qid, sid, gid, type, title, question, mandatory, question_order) VALUES (1002, 0, $SID, 100, 'S', 'dep_code', 'Enter your Department Code (e.g., IT, SALES, HR):', 'Y', 2)"

# Q3: Q_Sales (Broken Quote: "SALES)
limesurvey_query "INSERT INTO lime_questions (qid, parent_qid, sid, gid, type, title, question, mandatory, question_order, relevance) VALUES (1003, 0, $SID, 100, 'T', 'Q_Sales', 'Describe your sales targets for Q1:', 'N', 3, 'dep_code.NAOK == \"SALES')"

# Q4: Q_Shift (Broken Operator: =)
limesurvey_query "INSERT INTO lime_questions (qid, parent_qid, sid, gid, type, title, question, mandatory, question_order, relevance) VALUES (1004, 0, $SID, 100, 'T', 'Q_Shift', 'Preferred shift timing:', 'N', 4, 'dep_code.NAOK = \"OPS\"')"

# Q5: Q_NetSpeed
limesurvey_query "INSERT INTO lime_questions (qid, parent_qid, sid, gid, type, title, question, mandatory, question_order) VALUES (1005, 0, $SID, 101, 'N', 'Q_NetSpeed', 'Current download speed (Mbps):', 'N', 1)"

# 4. Add Answer Options for work_mode
limesurvey_query "INSERT INTO lime_answers (qid, code, sortorder, assessment_value, scale_id) VALUES (1001, 'Onsite', 1, 0, 0), (1001, 'Hybrid', 2, 0, 0), (1001, 'Remote', 3, 0, 0)"
limesurvey_query "INSERT INTO lime_answer_l10ns (id, aid, answer, language) SELECT NULL, aid, code, 'en' FROM lime_answers WHERE qid=1001"

# Record initial state
echo "Initial setup complete. Survey ID: $SID"
date +%s > /tmp/task_start_time.txt
limesurvey_query "SELECT relevance FROM lime_groups WHERE gid=101" > /tmp/initial_group_relevance.txt

# Ensure Firefox is focused and ready
echo "Launching Firefox..."
focus_firefox
# Navigate to admin login if not already there
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="