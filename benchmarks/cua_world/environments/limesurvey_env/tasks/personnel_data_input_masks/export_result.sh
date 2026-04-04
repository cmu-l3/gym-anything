#!/bin/bash
echo "=== Exporting Personnel Data Input Masks Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# We will use a Python script to query the database and generate a clean JSON result.
# The environment has python3-mysql.connector installed.

cat > /tmp/query_survey_data.py << 'EOF'
import mysql.connector
import json
import sys

try:
    conn = mysql.connector.connect(
        host='limesurvey-db',
        user='limesurvey',
        password='limesurvey_pass',
        database='limesurvey'
    )
    cursor = conn.cursor(dictionary=True)

    # 1. Find the survey by title
    # We use LIKE to be slightly flexible with case or trailing spaces, though task requires exact match
    cursor.execute("SELECT s.sid, s.active, sl.surveyls_title FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Personnel Data Verification 2025%' ORDER BY s.datecreated DESC LIMIT 1")
    survey = cursor.fetchone()

    result = {
        "survey_found": False,
        "survey_active": "N",
        "survey_title": "",
        "questions": []
    }

    if survey:
        result["survey_found"] = True
        result["survey_active"] = survey["active"]
        result["survey_title"] = survey["surveyls_title"]
        sid = survey["sid"]

        # 2. Get all questions for this survey
        # Join with l10ns to get the question text
        query_qs = f"""
            SELECT q.qid, q.title, q.type, ql.question 
            FROM lime_questions q 
            JOIN lime_question_l10ns ql ON q.qid = ql.qid 
            WHERE q.sid = {sid} AND q.parent_qid = 0 AND ql.language = 'en'
        """
        cursor.execute(query_qs)
        questions = cursor.fetchall()

        for q in questions:
            qid = q["qid"]
            q_data = {
                "qid": qid,
                "title": q["title"],
                "text": q["question"],
                "type": q["type"],
                "attributes": {}
            }

            # 3. Get attributes for each question
            cursor.execute(f"SELECT attribute, value FROM lime_question_attributes WHERE qid = {qid}")
            attrs = cursor.fetchall()
            for attr in attrs:
                q_data["attributes"][attr["attribute"]] = attr["value"]

            result["questions"].append(q_data)

    print(json.dumps(result, indent=2))

except Exception as e:
    error_res = {"error": str(e), "survey_found": False}
    print(json.dumps(error_res))

finally:
    if 'conn' in locals() and conn.is_connected():
        cursor.close()
        conn.close()
EOF

# Run the python script using the ga user environment or root (docker access needed)
# Since we need to access docker network or linked container, running from host/workspace is fine
# provided python mysql connector can reach the db service.
# NOTE: In this environment, 'limesurvey-db' is the hostname in docker-compose. 
# Depending on how the agent container is networked, it might need 'localhost' if running INSIDE the container that has port mapped,
# or the docker container IP.
# The `setup_limesurvey.sh` maps port 3306 to localhost on the host. 
# So we should try connecting to '127.0.0.1' from the workspace script if 'limesurvey-db' doesn't resolve.
# Let's adjust the host to 127.0.0.1 since the script runs in the VM where port 3306 is mapped.

sed -i "s/host='limesurvey-db'/host='127.0.0.1'/g" /tmp/query_survey_data.py

# Install connector if missing (safety check, though env spec says it's there)
# pip3 install mysql-connector-python > /dev/null 2>&1 || true

# Execute the query script
echo "Querying database..."
python3 /tmp/query_survey_data.py > /tmp/db_result.json 2> /tmp/db_error.log

# Combine with timestamp info
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "db_data": $(cat /tmp/db_result.json)
}
EOF

# Clean up and set permissions
chmod 666 /tmp/task_result.json
rm -f /tmp/query_survey_data.py

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="