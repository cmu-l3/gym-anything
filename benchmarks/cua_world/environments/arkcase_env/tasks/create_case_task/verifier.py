#!/usr/bin/env python3
"""
Verifier for create_case_task@1.
Verifies that a specific task was created within a specific ArkCase complaint case.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils from gym_anything
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_case_task(traj, env_info, task_info):
    """
    Verify the agent created the task correctly.
    
    Criteria:
    1. Task exists with correct Title (25 pts)
    2. Task is linked to correct Parent Case (15 pts)
    3. Priority is High (10 pts)
    4. Due Date matches (10 pts)
    5. Details contain required text (10 pts)
    6. Task Count increased (Anti-gaming) (10 pts)
    7. VLM verification of workflow (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_task_title', 'Review Response Package for Completeness')
    expected_case_title = metadata.get('target_case_title', '')
    expected_priority = metadata.get('expected_priority', 'High')
    expected_due_date = metadata.get('expected_due_date', '2025-08-01')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_found = result.get('task_found', False)
    task_data = result.get('task_data', {})
    initial_count = result.get('initial_task_count', 0)
    current_count = result.get('current_task_count', 0)
    parent_case_num = result.get('case_number', '')

    # 1. Check Task Existence & Title (25 pts)
    if task_found:
        title = task_data.get('title_parseable', task_data.get('name', ''))
        if expected_title.lower() in title.lower():
            score += 25
            feedback_parts.append(f"✅ Task created with correct title")
        else:
            score += 10 # Partial credit for creating *a* task that matched keyword search
            feedback_parts.append(f"⚠️ Task found but title mismatch ('{title}')")
    else:
        feedback_parts.append("❌ Target task not found")

    # 2. Check Parent Linkage (15 pts)
    # The API query in export_result.sh filtered by parent number, but let's double check
    if task_found:
        # Check if parent number in task data matches expected
        task_parent = task_data.get('parent_number_lcs', '')
        if parent_case_num and parent_case_num in task_parent:
            score += 15
            feedback_parts.append("✅ Linked to correct parent case")
        else:
            feedback_parts.append(f"⚠️ Parent case mismatch (Expected {parent_case_num}, got {task_parent})")

    # 3. Check Priority (10 pts)
    if task_found:
        priority = task_data.get('priority_lcs', task_data.get('priority', ''))
        if expected_priority.lower() == priority.lower():
            score += 10
            feedback_parts.append("✅ Priority set to High")
        else:
            feedback_parts.append(f"❌ Priority mismatch ({priority})")

    # 4. Check Dates (10 pts)
    if task_found:
        # Date format in Solr usually ISO string
        due_date = task_data.get('dueDate_tdt', task_data.get('due_tdt', ''))
        if expected_due_date in due_date:
            score += 10
            feedback_parts.append("✅ Due date correct")
        else:
            feedback_parts.append(f"❌ Due date mismatch ({due_date})")

    # 5. Check Details Content (10 pts)
    if task_found:
        details = task_data.get('details_no_html_tags_parseable', task_data.get('details', ''))
        keywords = ["FOIA response", "Exemption 5"]
        found_keywords = [k for k in keywords if k.lower() in details.lower()]
        if len(found_keywords) == len(keywords):
            score += 10
            feedback_parts.append("✅ Details contain required info")
        elif found_keywords:
            score += 5
            feedback_parts.append("⚠️ Details missing some info")
        else:
            feedback_parts.append("❌ Details text missing or incorrect")

    # 6. Anti-Gaming: Count Increase (10 pts)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("✅ Task count increased")
    else:
        feedback_parts.append("❌ No new tasks detected for case")

    # 7. VLM Verification (20 pts)
    # We use trajectory frames to verify they actually filled the form
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_parts.append("⚠️ No frames for VLM verification")
    else:
        vlm_prompt = (
            "Analyze these screenshots of a user interacting with ArkCase software. "
            "1. Did the user navigate to a case titled 'Henderson v. DOJ'? "
            "2. Did they open a 'New Task' form? "
            "3. Is there evidence of typing 'Review Response Package' or selecting a date? "
            "Return JSON: { 'case_navigated': bool, 'form_opened': bool, 'typing_evidence': bool }"
        )
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            vlm_score = 0
            if parsed.get('case_navigated'): vlm_score += 5
            if parsed.get('form_opened'): vlm_score += 10
            if parsed.get('typing_evidence'): vlm_score += 5
            
            score += vlm_score
            if vlm_score >= 10:
                feedback_parts.append(f"✅ VLM verified workflow ({vlm_score}/20 pts)")
            else:
                feedback_parts.append(f"⚠️ VLM workflow unclear ({vlm_score}/20 pts)")
        else:
            # Fallback if VLM fails but task exists
            if task_found:
                score += 10
                feedback_parts.append("⚠️ VLM failed, partial credit based on result")

    # Final Verdict
    # Mandatory: Must have found task and correct title
    passed = (score >= 60) and task_found and (expected_title.lower() in task_data.get('title_parseable', '').lower())

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }