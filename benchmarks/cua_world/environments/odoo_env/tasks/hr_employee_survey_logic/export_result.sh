#!/bin/bash
# Export script for hr_employee_survey_logic task
# Queries the database to verify the survey structure and conditional logic.

echo "=== Exporting Survey Task Result ==="

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python/XML-RPC to inspect the survey structure
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

result = {
    "survey_found": False,
    "questions": [],
    "logic_correct": False,
    "matrix_structure": {}
}

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result["error"] = str(e)
    with open('/tmp/hr_survey_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Find the survey
target_title = "Remote Work Readiness 2026"
surveys = execute('survey.survey', 'search_read', 
    [[['title', 'ilike', target_title]]], 
    {'fields': ['id', 'title', 'state'], 'limit': 1})

if surveys:
    survey = surveys[0]
    result["survey_found"] = True
    result["survey_id"] = survey['id']
    result["survey_title"] = survey['title']
    
    # Get questions
    questions = execute('survey.question', 'search_read',
        [[['survey_id', '=', survey['id']]]],
        {'fields': [
            'id', 'title', 'question_type', 
            'is_conditional', 'triggering_question_id', 'triggering_answer_ids',
            'suggested_answer_ids', 'matrix_row_ids'
        ], 'order': 'sequence'})
        
    for q in questions:
        q_data = {
            "title": q['title'],
            "type": q['question_type'],
            "is_conditional": q.get('is_conditional', False),
            "trigger_question_id": q.get('triggering_question_id', [False])[0] if q.get('triggering_question_id') else False
        }
        
        # If it's the logic question, check triggers details
        if q.get('is_conditional'):
            # Fetch names of triggering answers
            trigger_ids = q.get('triggering_answer_ids', [])
            if trigger_ids:
                triggers = execute('survey.question.answer', 'read', [trigger_ids], {'fields': ['value']})
                q_data['trigger_values'] = [t['value'] for t in triggers]
                
        # If it's a matrix or multiple choice, fetch answers/rows
        if q['question_type'] in ['simple_choice', 'multiple_choice', 'matrix']:
            # Fetch columns/choices
            if q.get('suggested_answer_ids'):
                answers = execute('survey.question.answer', 'read', [q['suggested_answer_ids']], {'fields': ['value']})
                q_data['answers'] = [a['value'] for a in answers]
            
            # Fetch rows (for matrix)
            if q.get('matrix_row_ids'):
                rows = execute('survey.question.answer', 'read', [q['matrix_row_ids']], {'fields': ['value']})
                q_data['rows'] = [r['value'] for r in rows]
                
        result["questions"].append(q_data)

# Save result
with open('/tmp/hr_survey_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

chmod 666 /tmp/hr_survey_result.json 2>/dev/null || true
cat /tmp/hr_survey_result.json