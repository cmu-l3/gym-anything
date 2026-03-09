#!/bin/bash
echo "=== Exporting Quota Demographic Sampling Results ==="

source /workspace/scripts/task_utils.sh

# Get Survey ID
if [ -f /tmp/task_survey_id.txt ]; then
    SID=$(cat /tmp/task_survey_id.txt)
else
    # Fallback: try to find by name
    SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title='Consumer Electronics Satisfaction Study Q4 2024' LIMIT 1")
fi

if [ -z "$SID" ]; then
    echo "Error: Survey ID not found."
    exit 1
fi

echo "Exporting data for Survey ID: $SID"

# 1. Check if Survey is Active
IS_ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID")

# 2. Get Quota Data
# We need: Quota Name, Limit, and Linked Answer Code
# This requires joining lime_quota, lime_quota_languagesettings, and lime_quota_members

# Construct a JSON structure of the quotas
# Note: outputting valid JSON from bash/mysql loop can be tricky, using Python helper
python3 << PYEOF
import json
import pymysql
import os

# Database connection
conn = pymysql.connect(
    host='limesurvey-db',
    user='limesurvey',
    password='limesurvey_pass',
    database='limesurvey',
    cursorclass=pymysql.cursors.DictCursor
)

sid = int("$SID")
result_data = {
    "survey_id": sid,
    "active": "$IS_ACTIVE",
    "quotas": []
}

try:
    with conn.cursor() as cursor:
        # Get all quotas for this survey
        # ql_limit is in lime_quota
        # quotals_name, quotals_message are in lime_quota_languagesettings
        sql_quotas = """
            SELECT q.id as quota_id, q.ql_limit, q.action, 
                   ql.quotals_name, ql.quotals_message
            FROM lime_quota q
            LEFT JOIN lime_quota_languagesettings ql ON q.id = ql.quotals_quota_id
            WHERE q.sid = %s
        """
        cursor.execute(sql_quotas, (sid,))
        quotas = cursor.fetchall()
        
        for q in quotas:
            q_obj = {
                "id": q["quota_id"],
                "limit": q["ql_limit"],
                "action": q["action"], # 1 = Terminate
                "name": q["quotals_name"],
                "message": q["quotals_message"],
                "members": []
            }
            
            # Get members (the linked answers) for this quota
            sql_members = """
                SELECT qm.code, qm.qid
                FROM lime_quota_members qm
                WHERE qm.quota_id = %s
            """
            cursor.execute(sql_members, (q["quota_id"],))
            members = cursor.fetchall()
            
            for m in members:
                q_obj["members"].append({
                    "qid": m["qid"],
                    "answer_code": m["code"]
                })
                
            result_data["quotas"].append(q_obj)

finally:
    conn.close()

# Save to file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result_data, f, indent=4)

print("JSON export successful")
PYEOF

# Take final screenshot
take_screenshot /tmp/task_final.png

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json