#!/bin/bash
echo "=== Exporting PSS-10 Task Result ==="

source /workspace/scripts/task_utils.sh

# Get Survey ID
SID=$(cat /tmp/pss10_sid.txt 2>/dev/null || \
      limesurvey_query "SELECT sid FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%PSS-10%' LIMIT 1")

if [ -z "$SID" ]; then
    echo "CRITICAL: PSS-10 Survey not found!"
    SID="0"
fi

echo "Checking Survey ID: $SID"

# 1. Check if Assessments are enabled and Survey is active
SURVEY_STATUS=$(limesurvey_query "SELECT assessments, active FROM lime_surveys WHERE sid=$SID")
ASSESSMENTS_ENABLED=$(echo "$SURVEY_STATUS" | awk '{print $1}')
IS_ACTIVE=$(echo "$SURVEY_STATUS" | awk '{print $2}')

# 2. Check Assessment Values for Reverse-Scored Items (PSS04, PSS05, PSS07, PSS08)
# We expect Code 0 -> Value 4, Code 4 -> Value 0
# Export format: QuestionTitle|Code|Value
REVERSE_ITEMS_DATA=$(limesurvey_query "SELECT q.title, a.code, a.assessment_value 
FROM lime_answers a 
JOIN lime_questions q ON a.qid=q.qid 
WHERE q.sid=$SID AND q.title IN ('PSS04','PSS05','PSS07','PSS08') 
ORDER BY q.title, a.code")

# 3. Check Assessment Values for Forward-Scored Items (Sanity check - PSS01)
FORWARD_ITEMS_DATA=$(limesurvey_query "SELECT q.title, a.code, a.assessment_value 
FROM lime_answers a 
JOIN lime_questions q ON a.qid=q.qid 
WHERE q.sid=$SID AND q.title='PSS01' 
ORDER BY q.title, a.code")

# 4. Check Assessment Rules
# Export format: Min|Max|Name|Message
RULES_DATA=$(limesurvey_query "SELECT minimum, maximum, name, message 
FROM lime_assessments 
WHERE sid=$SID 
ORDER BY minimum")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON Export
# We use Python to format the SQL output into valid JSON to avoid Bash escaping hell
python3 - << PYEOF
import json
import sys

def parse_sql_rows(raw_data, columns):
    rows = []
    if not raw_data: 
        return rows
    lines = raw_data.strip().split('\n')
    for line in lines:
        if not line.strip(): continue
        parts = line.split('\t')
        row_dict = {}
        for i, col in enumerate(columns):
            if i < len(parts):
                row_dict[col] = parts[i]
        rows.append(row_dict)
    return rows

reverse_raw = """$REVERSE_ITEMS_DATA"""
forward_raw = """$FORWARD_ITEMS_DATA"""
rules_raw = """$RULES_DATA"""

result = {
    "survey_id": "$SID",
    "assessments_enabled": "$ASSESSMENTS_ENABLED",
    "is_active": "$IS_ACTIVE",
    "reverse_items": parse_sql_rows(reverse_raw, ["title", "code", "value"]),
    "forward_items": parse_sql_rows(forward_raw, ["title", "code", "value"]),
    "rules": parse_sql_rows(rules_raw, ["min", "max", "name", "message"]),
    "timestamp": "$(date -Iseconds)"
}

with open("/tmp/pss10_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("JSON export created at /tmp/pss10_result.json")
PYEOF

# Secure copy
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/pss10_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

cat /tmp/task_result.json
echo "=== Export Complete ==="