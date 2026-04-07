#!/usr/bin/env python3
import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_escalate_safety_issue_via_search(traj, env_info, task_info):
    """
    Verifies the safety escalation task.
    Criteria:
    1. Target issue priority updated to 'Immediate'.
    2. Target issue assigned to 'Marcus Thorne'.
    3. Target issue updated AFTER task start.
    4. Decoy issues NOT updated (false positives).
    5. VLM: Search functionality used.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result load failed: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Internal error: {result['error']}"}

    score = 0
    feedback = []
    
    # Extract data
    target = result.get('target', {})
    expected = result.get('expected', {})
    decoys = result.get('decoys', [])
    task_start = int(result.get('task_start_time', 0))

    # Criterion 1: Priority Update (30 pts)
    # Check if current priority ID matches expected Immediate ID
    if target.get('priority_id') == expected.get('immediate_priority_id'):
        score += 30
        feedback.append("Priority correctly set to Immediate.")
    else:
        feedback.append("Priority NOT set to Immediate.")

    # Criterion 2: Assignee Update (30 pts)
    if target.get('assigned_to_id') == expected.get('marcus_id'):
        score += 30
        feedback.append("Assignee correctly set to Marcus Thorne.")
    else:
        feedback.append("Assignee NOT set to Marcus Thorne.")

    # Criterion 3: Modification Check (20 pts)
    updated_on = target.get('updated_on', 0)
    if updated_on > task_start:
        score += 20
        feedback.append("Target issue was modified during task.")
    else:
        feedback.append("Target issue was NOT modified (timestamp check failed).")

    # Criterion 4: Decoy Check (10 pts)
    # Ensure no decoy issues were modified after task start
    decoys_modified = [d['subject'] for d in decoys if d['updated_on'] > task_start]
    if not decoys_modified:
        score += 10
        feedback.append("No decoy issues were modified.")
    else:
        feedback.append(f"Penalty: Decoy issues modified ({len(decoys_modified)}).")

    # Criterion 5: VLM Check for Search Usage (10 pts)
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of a Redmine user session.
        Did the user perform a SEARCH?
        Look for:
        1. Text typed into the top-right search bar.
        2. A search results page listing multiple issues.
        3. Application of filters on the issue list page.
        
        Answer JSON: {"search_used": boolean}
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('parsed', {}).get('search_used', False):
                score += 10
                feedback.append("VLM confirmed search usage.")
            else:
                feedback.append("VLM did not detect search usage.")
        except:
            # Fallback if VLM fails, give benefit of doubt if other criteria met
            if score >= 80:
                score += 10
    
    # Pass threshold
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }