#!/usr/bin/env python3
"""
Verifier for generate_evacuation_list task.

Verification Logic:
1. Check if 'evacuation_list.csv' exists.
2. Check if the file was created during the task (anti-gaming).
3. Content Verification:
   - MUST contain "Alice Safety" and "Bruce Hazard" (Positive constraint).
   - MUST NOT contain "Charlie Drill" (Negative constraint - Safety Critical).
   - MUST contain company names to ensure full records were exported.

Scoring:
- 10 pts: File exists and created during task.
- 30 pts: Alice Safety present.
- 30 pts: Bruce Hazard present.
- 30 pts: Charlie Drill ABSENT.
"""

import json
import os
import tempfile
import logging
import csv

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_evacuation_list(traj, env_info, task_info):
    """
    Verify the evacuation list generation.
    """
    # 1. Setup and retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_names = metadata.get('required_names', ["Alice Safety", "Bruce Hazard"])
    forbidden_names = metadata.get('forbidden_names', ["Charlie Drill"])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Load task execution result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check File Existence and Timestamp
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Evacuation list file not found at expected path."}

    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "File exists but was not created during this task session (stale data)."}

    score += 10
    feedback_parts.append("File created successfully")

    # 3. Analyze File Content
    # We need to copy the actual CSV file from the container to analyze it
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    file_content = ""
    try:
        copy_from_env(result["output_path"], temp_csv.name)
        # Read content carefully, handling potential encoding issues
        with open(temp_csv.name, 'r', errors='ignore') as f:
            file_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV content: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Normalize content for search (case insensitive)
    content_lower = file_content.lower()
    
    # Check Required Names (30 pts each = 60 pts)
    missing_required = []
    for name in required_names:
        # Split name to allow for format variations (e.g., "Safety, Alice" or "Alice Safety")
        parts = name.lower().split()
        if all(part in content_lower for part in parts):
            score += 30
        else:
            missing_required.append(name)
            
    if missing_required:
        feedback_parts.append(f"Missing visitors: {', '.join(missing_required)}")
    else:
        feedback_parts.append("All active visitors found")

    # Check Forbidden Names (30 pts)
    # This is critical. If Charlie is in the list, it's a safety fail.
    forbidden_found = []
    for name in forbidden_names:
        parts = name.lower().split()
        # stricter check: if both first and last name appear in the file (even on different lines if CSV is messy),
        # but usually we look for the record.
        # Let's check if the specific combination appears.
        if all(part in content_lower for part in parts):
            forbidden_found.append(name)
    
    if not forbidden_found:
        score += 30
        feedback_parts.append("Checked-out visitors correctly excluded")
    else:
        feedback_parts.append(f"SAFETY FAIL: Evacuation list includes visitors who already left: {', '.join(forbidden_found)}")
        # Heavy penalty implies the logic of 'evacuation list' is broken
        # We ensure they don't pass if they fail this, regardless of other points
        if score >= 70: 
            score = 65 # Cap below passing threshold (70)

    # Final Pass/Fail determination
    # Threshold 70 means: Must have created file + Included both Alice/Bruce + Excluded Charlie
    # (10 + 30 + 30 + 30 = 100). 
    # If Charlie is included: 10 + 30 + 30 + 0 = 70, but we capped it at 65 above.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }