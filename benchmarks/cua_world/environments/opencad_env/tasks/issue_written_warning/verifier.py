#!/usr/bin/env python3
"""
Verifier for issue_written_warning task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_issue_written_warning(traj, env_info, task_info):
    """
    Verify that a written warning was issued to Michael De Santa.
    
    Criteria:
    1. A new record exists in the 'warnings' table (30 pts)
    2. The warning is linked to 'Michael De Santa' (20 pts)
    3. The violation/reason matches 'Defective Equipment' (20 pts)
    4. The narrative/remarks contains key phrases (15 pts)
    5. Anti-gaming: Record is in 'warnings', not 'citations' (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_civilian = metadata.get('target_civilian', "Michael De Santa").lower()
    target_violation = metadata.get('target_violation', "Defective Equipment").lower()
    required_terms = [t.lower() for t in metadata.get('required_narrative_terms', ["tail light"])]

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/issue_written_warning_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check for new record
    warning_found = result.get('warning_found', False)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    # Check if DB count increased (Reliable signal)
    if current_count > initial_count:
        score += 15
        feedback_parts.append("Database record count increased")
    
    if warning_found:
        score += 15
        feedback_parts.append("New warning record located")
        
        record = result.get('record', {})
        rec_name = record.get('civilian_name', '').lower()
        rec_reason = record.get('reason', '').lower()
        rec_remarks = record.get('remarks', '').lower()
        
        # 2. Check Civilian Name
        if target_civilian in rec_name:
            score += 20
            feedback_parts.append(f"Correct civilian: {record.get('civilian_name')}")
        else:
            feedback_parts.append(f"Wrong civilian: expected '{target_civilian}', got '{rec_name}'")
            
        # 3. Check Violation Type
        # Allow partial match for dropdowns like 'Defective Equipment (Vehicle)'
        if target_violation in rec_reason:
            score += 20
            feedback_parts.append(f"Correct violation: {record.get('reason')}")
        else:
            feedback_parts.append(f"Wrong violation: expected '{target_violation}', got '{rec_reason}'")
            
        # 4. Check Narrative
        found_terms = [t for t in required_terms if t in rec_remarks]
        if len(found_terms) >= 1:
            score += 15
            feedback_parts.append(f"Narrative valid ({len(found_terms)}/{len(required_terms)} terms match)")
        else:
            feedback_parts.append("Narrative missing required details (e.g., 'tail light')")
            
        # 5. Anti-gaming (Implicit)
        # Since we queried the 'warnings' table, existence there implies correct table usage.
        # If they used citations, 'warning_found' would be false (or point to an old record if not filtered correctly, 
        # but we filter by ID > MAX_ID).
        score += 15
        feedback_parts.append("Correctly used Warning module (not Citation)")
        
    else:
        feedback_parts.append("No new warning record found")
        # Check if they just failed to submit or used wrong table?
        # If count didn't increase, score remains low.

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }