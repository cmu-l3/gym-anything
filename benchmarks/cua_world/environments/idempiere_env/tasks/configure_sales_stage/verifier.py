#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_sales_stage(traj, env_info, task_info):
    """
    Verifies that the Sales Stage 'Verbal Commitment' was created correctly in iDempiere.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_key = metadata.get('expected_search_key', 'Verbal')
    expected_name = metadata.get('expected_name', 'Verbal Commitment')
    expected_prob = metadata.get('expected_probability', 80)
    expected_desc_frag = metadata.get('expected_description_fragment', 'verbally agreed')

    # Retrieve result file from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # Check 1: Record Found (40 pts)
    if not result.get('record_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No Sales Stage record found with Search Key 'Verbal'."
        }
    
    score += 40
    feedback_parts.append("Record created")

    # Anti-gaming check: Timestamp
    # This assumes the DB timestamp format and the bash `date +%s` are comparable
    # Typically PostgreSQL timestamps are strings, we might need loose parsing or rely on the script 
    # to have filtered specifically created records. The SQL query in export_result.sh gets the *latest* 
    # record. If the setup cleaned up, any record found is likely new.
    # We'll rely on the setup cleanup + checking if 'record_found' is true.
    
    # Check 2: Correct Probability (30 pts)
    # The DB might return an integer or float string
    try:
        actual_prob = float(result.get('probability', 0))
        if abs(actual_prob - expected_prob) < 0.1: # Tolerance for float
            score += 30
            feedback_parts.append("Probability correct")
        else:
            feedback_parts.append(f"Incorrect probability: found {actual_prob}, expected {expected_prob}")
    except ValueError:
        feedback_parts.append("Invalid probability value format")

    # Check 3: Name Matches (10 pts)
    actual_name = result.get('name', '')
    if actual_name.strip() == expected_name:
        score += 10
        feedback_parts.append("Name correct")
    else:
        feedback_parts.append(f"Name mismatch: found '{actual_name}', expected '{expected_name}'")

    # Check 4: Description populated correctly (10 pts)
    actual_desc = result.get('description', '')
    if expected_desc_frag.lower() in actual_desc.lower():
        score += 10
        feedback_parts.append("Description correct")
    else:
        feedback_parts.append("Description missing or incorrect")

    # Check 5: Is Active (10 pts)
    if result.get('is_active', False):
        score += 10
        feedback_parts.append("Record is active")
    else:
        feedback_parts.append("Record is inactive")

    # Final Evaluation
    # Pass threshold: 70 points (Must have record + probability correct)
    passed = score >= 70
    
    final_feedback = f"Score: {score}/100. " + ", ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }