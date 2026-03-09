#!/bin/bash
echo "=== Exporting Insurance Claims Upload Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use a Python script to extract the complex relational data 
# (Surveys -> Questions -> Attributes) and export it to JSON.
# This avoids complex bash string parsing.

cat > /tmp/extract_survey_config.py << 'PYEOF'
import json
import mysql.connector
import os
import sys

# Database config (matching docker-compose)
DB_CONFIG = {
    'user': 'limesurvey',
    'password': 'limesurvey_pass',
    'host': 'limesurvey-db', # Accessed via docker network if running inside, but here we run on host accessing container
    'database': 'limesurvey',
}

# Since we are running in the VM, we access the DB container via docker exec
# But for simplicity in this script, we'll shell out to the docker exec command
# or use the pre-configured python environment if it has access.
# The easiest robust way in this env is to use the `limesurvey_query` helper 
# logic, but implementing complex logic in bash is hard.
# We will generate SQL queries and parse the output.

def run_query(query):
    # Escape double quotes in query for the bash command
    query = query.replace('"', '\\"')
    cmd = f'docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "{query}"'
    try:
        stream = os.popen(cmd)
        return stream.read().strip()
    except Exception as e:
        return ""

def get_survey_info():
    # Find survey by title
    sql = "SELECT s.sid, sl.surveyls_title, s.active FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Insurance Claim%' ORDER BY s.datecreated DESC LIMIT 1"
    res = run_query(sql)
    if not res:
        return None
    parts = res.split('\t')
    if len(parts) < 3: return None
    return {'sid': parts[0], 'title': parts[1], 'active': parts[2]}

def get_question_info(sid, code):
    # Get basic question info: qid, type, relevance (logic)
    sql = f"SELECT qid, type, relevance FROM lime_questions WHERE sid={sid} AND title='{code}' LIMIT 1"
    res = run_query(sql)
    if not res:
        return None
    parts = res.split('\t')
    return {'qid': parts[0], 'type': parts[1], 'relevance': parts[2]}

def get_question_attribute(qid, attribute_name):
    sql = f"SELECT value FROM lime_question_attributes WHERE qid={qid} AND attribute='{attribute_name}' LIMIT 1"
    res = run_query(sql)
    return res if res else None

def main():
    result = {
        'survey_found': False,
        'survey_active': False,
        'questions': {}
    }

    survey = get_survey_info()
    if survey:
        result['survey_found'] = True
        result['survey_title'] = survey['title']
        result['survey_active'] = (survey['active'] == 'Y')
        sid = survey['sid']

        # Check specific questions
        target_questions = ['HAS_EVIDENCE', 'FORM_PDF', 'DMG_PHOTOS']
        
        for code in target_questions:
            q_info = get_question_info(sid, code)
            if q_info:
                q_data = {
                    'exists': True,
                    'type': q_info['type'],
                    'relevance': q_info['relevance'],
                    'attributes': {}
                }
                
                # If it's a file upload question ('|'), get attributes
                if q_info['type'] == '|':
                    # Check allowed filetypes
                    ft = get_question_attribute(q_info['qid'], 'allowed_filetypes')
                    if ft: q_data['attributes']['allowed_filetypes'] = ft
                    
                    # Check max files
                    mf = get_question_attribute(q_info['qid'], 'max_num_of_files')
                    if mf: q_data['attributes']['max_num_of_files'] = mf
                
                result['questions'][code] = q_data
            else:
                result['questions'][code] = {'exists': False}

    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
PYEOF

# Run the python script and save result
python3 /tmp/extract_survey_config.py > /tmp/config_result.json

# Safe export
export_json_result "$(cat /tmp/config_result.json)" "/tmp/task_result.json"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="