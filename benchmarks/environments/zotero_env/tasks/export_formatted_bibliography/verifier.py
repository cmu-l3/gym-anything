#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_export_formatted_bibliography(traj, env_info, task_info):
    """
    Verify the export_formatted_bibliography task.
    
    Expected behavior:
    1. Output file exists at correct path.
    2. File was created/modified during the task window.
    3. File contains HTML formatted bibliography.
    4. File contains key author names/titles corresponding to the collection.
    """
    
    # 1. Retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    file_exists = result.get("file_exists", False)
    created_during = result.get("file_created_during_task", False)
    file_size = result.get("file_size", 0)
    has_html = result.get("has_html_tags", False)
    entry_count = result.get("entry_count", 0)
    content = result.get("content_check", {})

    score = 0
    feedback = []

    # 3. Score Calculation
    
    # Criterion A: File Creation (20 pts)
    if file_exists:
        if created_during:
            score += 20
            feedback.append("Output file created successfully.")
        else:
            score += 5
            feedback.append("Output file exists but timestamp is old (reused previous file?).")
    else:
        feedback.append("Output file not found at expected path.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion B: File Format (20 pts)
    if has_html:
        score += 20
        feedback.append("File appears to be HTML.")
    else:
        feedback.append("File is not HTML formatted.")
        # We don't fail immediately, but score will be low

    # Criterion C: Content Validity (40 pts)
    # We check for 5 items. 8 pts each.
    items_found = 0
    if content.get("shannon"): items_found += 1
    if content.get("turing"): items_found += 1
    if content.get("vaswani"): items_found += 1
    if content.get("lecun"): items_found += 1
    if content.get("resnet"): items_found += 1
    
    content_score = items_found * 8
    score += content_score
    feedback.append(f"Found {items_found}/5 expected bibliography entries.")

    # Criterion D: Validity/Size check (20 pts)
    # A bibliography with 5 items in HTML should be at least a few hundred bytes
    if file_size > 500:
        score += 10
        feedback.append("File size is reasonable.")
    elif file_size > 0:
        score += 5
        feedback.append("File is very small.")
        
    # Check entry count roughly matches
    if 4 <= entry_count <= 6:
        score += 10
        feedback.append(f"Entry count ({entry_count}) is correct.")
    elif entry_count > 0:
        score += 5
        feedback.append(f"Entry count ({entry_count}) is suspicious (expected 5).")

    # 4. Final Verdict
    # Pass threshold: 60 points
    # Must have created the file and found at least 3 correct items
    passed = (score >= 60) and created_during and (items_found >= 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }