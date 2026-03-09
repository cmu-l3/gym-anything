#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_dividend_income_report(traj, env_info, task_info):
    """
    Verifies that the agent calculated the correct dividend total and saved it to a file.
    """
    # 1. Setup: Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Metadata
    metadata = task_info.get('metadata', {})
    expected_val = metadata.get('expected_value', 110.25)
    tolerance = metadata.get('tolerance', 0.1)

    # 3. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence (20 pts)
    if result.get('output_exists'):
        score += 20
        feedback_parts.append("Report file exists")
    else:
        feedback_parts.append("Report file not found")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback_parts)}

    # Criterion 2: Anti-Gaming / Freshness (10 pts)
    if result.get('file_created_during_task'):
        score += 10
    else:
        feedback_parts.append("File timestamp indicates pre-existence")

    # Criterion 3: Content Accuracy (70 pts)
    content = result.get('file_content', '')
    
    # Parse number from content (remove currency symbols like $)
    # Regex to find float number
    match = re.search(r"[-+]?\d*\.\d+|\d+", content)
    
    if match:
        try:
            val = float(match.group())
            diff = abs(val - expected_val)
            if diff <= tolerance:
                score += 70
                feedback_parts.append(f"Value correct: {val}")
            else:
                feedback_parts.append(f"Value incorrect: got {val}, expected {expected_val}")
        except ValueError:
            feedback_parts.append(f"Could not parse number from: {content}")
    else:
        feedback_parts.append(f"No number found in file content: '{content}'")

    # 5. Determine Pass/Fail
    passed = score >= 90  # Requires file existence + correct value
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }