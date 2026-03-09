#!/bin/bash
echo "=== Exporting PTO Date Calculation Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the survey ID for "PTO Request Form 2024"
SURVEY_ID=$(get_survey_id "PTO Request Form 2024")

SURVEY_FOUND="false"
QUESTIONS_JSON="[]"
ACTIVE="N"

if [ -n "$SURVEY_ID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey ID: $SURVEY_ID"
    
    # Check if active
    ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SURVEY_ID")
    
    # Export questions and their attributes
    # We need: title (code), type, question (text/equation), relevance
    # AND for the 'return' question, we need the validation attribute from lime_question_attributes
    
    # Python script to extract complex data structure from DB
    python3 - << PYEOF
import mysql.connector
import json
import os

try:
    conn = mysql.connector.connect(
        host="limesurvey-db",
        user="limesurvey",
        password="limesurvey_pass",
        database="limesurvey"
    )
    cursor = conn.cursor(dictionary=True)
    
    sid = $SURVEY_ID
    
    # Get questions
    query = """
    SELECT q.qid, q.title as code, q.type, q.question, q.relevance, q.parent_qid
    FROM lime_questions q 
    WHERE q.sid = %s
    """
    cursor.execute(query, (sid,))
    questions = cursor.fetchall()
    
    # Get question attributes (like validation)
    # attribute 'em_validation_q' is the validation equation
    attr_query = """
    SELECT qid, attribute, value 
    FROM lime_question_attributes 
    WHERE attribute = 'em_validation_q'
    """
    cursor.execute(attr_query)
    attributes = cursor.fetchall()
    
    # Map attributes to questions
    attr_map = {a['qid']: a['value'] for a in attributes}
    
    # Clean up and combine
    final_questions = []
    for q in questions:
        # Get raw text from l10ns table if 'question' column is empty/xml (depends on version)
        # In newer LimeSurvey, question text is in lime_question_l10ns
        l10n_query = "SELECT question FROM lime_question_l10ns WHERE qid=%s AND language='en'"
        cursor.execute(l10n_query, (q['qid'],))
        res = cursor.fetchone()
        q_text = res['question'] if res else q['question']
        
        q_data = {
            "code": q['code'],
            "type": q['type'],
            "question_text": q_text, # For Equation type, this holds the equation
            "relevance": q['relevance'],
            "validation": attr_map.get(q['qid'], "")
        }
        final_questions.append(q_data)
        
    print(json.dumps(final_questions))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))

PYEOF
    > /tmp/questions_export.json
    
    QUESTIONS_JSON=$(cat /tmp/questions_export.json)
fi

# Construct result JSON
# Use python to safely construct JSON to avoid bash string escaping hell
python3 - << PYEOF
import json
import os

result = {
    "survey_found": "$SURVEY_FOUND" == "true",
    "survey_id": "$SURVEY_ID",
    "active": "$ACTIVE",
    "questions": json.loads('''$QUESTIONS_JSON''') if "$SURVEY_FOUND" == "true" else []
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="