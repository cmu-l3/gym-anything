#!/usr/bin/env python3
"""
Verifier for generate_pipeline_pivot_report task.

Verifies:
1. File existence and timestamp (Anti-gaming).
2. Content structure (Salesperson rows, Stage columns).
3. Data accuracy (Revenue sums match seeded data).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_pipeline_pivot_report(traj, env_info, task_info):
    """
    Verify the Odoo pivot report generation.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Extract metrics
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    content = result.get('content_verification', {})
    
    feedback_parts = []
    score = 0
    
    # Criterion 1: File Existence (10 pts)
    if output_exists:
        score += 10
        feedback_parts.append("File found")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file 'revenue_report.xlsx' not found in Documents."}
        
    # Criterion 2: File Creation Timestamp (Anti-gaming) (10 pts)
    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates it was not created during this session")
        
    # Criterion 3: Valid Content (readable Excel) (10 pts)
    if content.get('content_valid', False):
        score += 10
        feedback_parts.append("Valid Excel format")
    else:
        return {"passed": False, "score": score, "feedback": "File exists but is not a valid/readable Excel file."}
        
    # Criterion 4: Row Configuration (Salesperson) (25 pts)
    if content.get('has_salespeople', False):
        score += 25
        feedback_parts.append("Rows grouped by Salesperson")
    else:
        feedback_parts.append("Salespeople (Alice/Admin) not found in rows")
        
    # Criterion 5: Column Configuration (Stage) (25 pts)
    if content.get('has_stages', False):
        score += 25
        feedback_parts.append("Columns grouped by Stage")
    else:
        feedback_parts.append("Stages (New/Won) not found in columns")
        
    # Criterion 6: Values Match (Revenue) (20 pts)
    if content.get('values_correct', False):
        score += 20
        feedback_parts.append("Revenue values match database")
    else:
        feedback_parts.append("Revenue values do not match expected sums (Admin Won=50k, Alice Qual=25k)")
        
    # Optional bonus/penalty for clean measures
    if not content.get('clean_measures', False):
        feedback_parts.append("(Note: Extra measures like 'Count' detected)")
        
    # Pass threshold
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }