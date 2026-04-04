#!/bin/bash
echo "=== Exporting Change Risk Configuration ==="

# Source shared utilities for DB access
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Firefox is still running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# ==============================================================================
# Query the Database for Risk Configuration
# We need to fetch questions and their associated choices/scores.
# Note: Table names in SDP Postgres are often lowercase.
# ==============================================================================

# Create a temporary SQL script to extract data as JSON-like structure
# We select from RiskQuestion and RiskChoice tables
SQL_QUERY="
SELECT 
    q.question, 
    q.description, 
    c.choice, 
    c.score 
FROM riskquestion q 
JOIN riskchoice c ON q.questionid = c.questionid 
ORDER BY q.question, c.score;
"

# Execute query using the helper function
echo "Querying database..."
DB_OUTPUT=$(sdp_db_exec "$SQL_QUERY" "servicedesk")

# Save raw DB output for debugging
echo "$DB_OUTPUT" > /tmp/db_raw_output.txt

# Convert DB output (pipe-separated usually) to JSON
# The sdp_db_exec with -A -t produces output like:
# Question|Description|Choice|Score
# We will use python to parse this and create a structured JSON

python3 -c "
import json
import sys
import time

try:
    raw_data = '''$DB_OUTPUT'''
    questions = {}
    
    for line in raw_data.strip().split('\n'):
        if not line.strip(): continue
        parts = line.split('|')
        if len(parts) < 4: continue
        
        q_text = parts[0].strip()
        q_desc = parts[1].strip()
        c_text = parts[2].strip()
        c_score = parts[3].strip()
        
        try:
            score_int = int(c_score)
        except:
            score_int = 0
            
        if q_text not in questions:
            questions[q_text] = {
                'text': q_text,
                'description': q_desc,
                'choices': []
            }
        
        questions[q_text]['choices'].append({
            'text': c_text,
            'score': score_int
        })
    
    result = {
        'found_questions': list(questions.values()),
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'app_running': '$APP_RUNNING' == 'true'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error processing DB output: {e}')
    # Fallback empty JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'found_questions': []}, f)
"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json