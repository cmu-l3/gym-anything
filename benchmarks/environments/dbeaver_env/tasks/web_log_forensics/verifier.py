#!/usr/bin/env python3
"""
Verifier for web_log_forensics task.

Criteria:
1. Investigation DB created (10 pts)
2. Data imported successfully (20 pts)
3. Schema correct (status_code numeric) (10 pts)
4. Output CSV exists and created during task (10 pts)
5. Attacker IP identified in output (20 pts)
6. Breached file identified in output (30 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_web_log_forensics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    # 1. DB Created (10 pts)
    if result.get('db_exists'):
        score += 10
        feedback.append("Database created successfully.")
    else:
        feedback.append("FAIL: Investigation database not found.")
        
    # 2. Data Imported (20 pts)
    # Ground truth usually has ~2150 rows. Accept anything reasonable > 1000
    row_count = result.get('row_count', 0)
    if result.get('table_exists') and row_count > 1000:
        score += 20
        feedback.append(f"Data imported successfully ({row_count} rows).")
    elif result.get('table_exists'):
        score += 10
        feedback.append(f"Table created but row count low ({row_count}).")
    else:
        feedback.append("FAIL: 'web_logs' table not found.")

    # 3. Schema Quality (10 pts)
    if result.get('status_is_numeric'):
        score += 10
        feedback.append("Schema check passed: status_code is numeric.")
    else:
        feedback.append("Warning: status_code column does not appear to be numeric (check import settings).")

    # 4. Output File Existence (10 pts)
    if result.get('output_exists') and result.get('output_created_during_task'):
        score += 10
        feedback.append("Output CSV created.")
    elif result.get('output_exists'):
        feedback.append("Output CSV exists but timestamp is old (reused?).")
    else:
        feedback.append("FAIL: breach_evidence.csv not found.")

    # 5. Attacker ID (20 pts)
    if result.get('output_has_attacker'):
        score += 20
        feedback.append("Attacker IP correctly identified in report.")
    else:
        feedback.append("FAIL: Report does not contain the attacker IP.")

    # 6. Breach ID (30 pts)
    if result.get('output_has_breach'):
        score += 30
        feedback.append("Breached file correctly identified in report.")
    else:
        feedback.append("FAIL: Report does not contain the specific breached file.")

    # Penalty for too much noise in output
    # The output should ideally be 1 row (the breach). If > 10, they just dumped everything.
    output_rows = result.get('output_row_count', 0)
    if output_rows > 10 and result.get('output_has_breach'):
        score -= 10
        feedback.append(f"Penalty: Report contains too much noise ({output_rows} rows). Expected filtered results.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " ".join(feedback)
    }