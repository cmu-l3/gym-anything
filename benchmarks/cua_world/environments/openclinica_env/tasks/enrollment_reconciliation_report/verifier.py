#!/usr/bin/env python3
"""Verifier for enrollment_reconciliation_report task."""

import json
import tempfile
import os
import re
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
from vlm_utils import query_vlm as _query_vlm_direct

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """You are verifying if an AI agent properly navigated a Clinical Data Management system (OpenClinica) to gather data.

Review the provided screenshots from the agent's session.
1. Did the agent navigate through different sections of the OpenClinica web application?
2. Did the agent visit the "Subject Matrix" (or subject list) to view patient data?
3. Did the agent visit "Build Study", "View Study", or "Event Definitions" pages to see the study schedule?
4. Did the agent visit the "Users" or "Study Users" administration pages?
5. Does the sequence show genuine UI interaction (clicking links, viewing tables) rather than just a terminal window or direct database querying?

Respond in JSON format:
{
    "ui_interaction_found": true/false,
    "subject_matrix_visited": true/false,
    "study_events_visited": true/false,
    "users_page_visited": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "Brief explanation"
}
"""

def verify_enrollment_reconciliation_report(traj, env_info, task_info):
    """
    Verify the content of the enrollment reconciliation report.
    
    Scoring Strategy (100 points):
    1. File exists and was created/modified during task (10 pts)
    2. File structure: Headers exist (10 pts)
    3. Study Info: Name, Protocol, PI present and correct (15 pts)
    4. Subject Counts: Count matches (10 pts)
    5. Subject Details: ≥4 subjects with correct label, gender, DOB (25 pts)
    6. Event Definitions: 3 events listed correctly (15 pts)
    7. Study Users: Target users and roles listed correctly (15 pts)
    - Penalty: Up to -30 points if VLM does not confirm UI navigation (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_file = metadata.get('expected_file', '/home/ga/Documents/enrollment_reconciliation.txt')
    
    # 1. Load basic execution result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/enrollment_report_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": f"Report file {expected_file} was not found."}
    if not result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file exists but was not modified during the task."}

    # 2. Copy and read the actual report file
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(expected_file, temp_txt.name)
        with open(temp_txt.name, 'r', encoding='utf-8') as f:
            report_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy or read the report file: {e}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    score = 10
    feedback = ["File exists and was modified (+10)."]
    
    # 3. Check section headers
    headers = [
        "=== STUDY INFORMATION ===",
        "=== ENROLLED SUBJECTS ===",
        "=== EVENT DEFINITIONS ===",
        "=== STUDY USERS ==="
    ]
    headers_found = [h for h in headers if h in report_content]
    if len(headers_found) == 4:
        score += 10
        feedback.append("All required section headers found (+10).")
    else:
        feedback.append(f"Missing headers: {set(headers) - set(headers_found)}. Structure incomplete.")
        
    content_lower = report_content.lower()

    # 4. Study Info Check
    study_info = metadata.get('study_info', {})
    if "diabetes" in content_lower and "dm-trial-2024" in content_lower and "chen" in content_lower:
        score += 15
        feedback.append("Study Name, Protocol ID, and PI accurately reported (+15).")
    else:
        feedback.append("Study information (Name/Protocol/PI) missing or inaccurate.")

    # 5. Subject Count Check
    # The agent might say "5" or something else depending on how they counted "removed". Accept 4 or 5.
    if re.search(r'total subjects:\s*[45]', content_lower):
        score += 10
        feedback.append("Total subjects count is acceptable (+10).")
    else:
        feedback.append("Total subjects count missing or incorrect.")

    # 6. Subject Details Check
    expected_subjects = metadata.get('expected_subjects', [])
    subjects_correct = 0
    for subj in expected_subjects:
        # Require label, gender, and DOB fragments to exist near each other or on the same line
        label = subj['label'].lower()
        gender = subj['gender'].lower()
        dob = subj['dob']
        # Look for a line containing the label
        lines = content_lower.split('\n')
        for line in lines:
            if label in line:
                if (gender in line or gender[0] in line) and dob in line:
                    subjects_correct += 1
                    break
                    
    if subjects_correct >= 4:
        score += 25
        feedback.append(f"{subjects_correct}/5 subjects perfectly detailed (+25).")
    elif subjects_correct > 0:
        partial = subjects_correct * 5
        score += partial
        feedback.append(f"Only {subjects_correct}/5 subjects detailed correctly (+{partial}).")
    else:
        feedback.append("No subject details matched expected ground truth.")

    # 7. Event Definitions Check
    expected_events = metadata.get('expected_events', [])
    events_correct = 0
    for ev in expected_events:
        name = ev['name'].lower()
        if name in content_lower:
            events_correct += 1
            
    if events_correct == 3:
        score += 15
        feedback.append("All 3 Event Definitions listed (+15).")
    elif events_correct > 0:
        partial = events_correct * 5
        score += partial
        feedback.append(f"Only {events_correct}/3 Event Definitions listed (+{partial}).")
    else:
        feedback.append("No event definitions listed accurately.")

    # 8. Users Check
    expected_users = metadata.get('expected_users', [])
    users_correct = 0
    for u in expected_users:
        uname = u['username'].lower()
        urole = u['role'].lower()
        # They might format data_manager as "data manager"
        urole_clean = urole.replace('_', ' ')
        
        lines = content_lower.split('\n')
        for line in lines:
            if uname in line and (urole in line or urole_clean in line):
                users_correct += 1
                break
                
    if users_correct >= 2:
        score += 15
        feedback.append(f"Study users accurately listed (+15).")
    else:
        feedback.append("Study users missing or roles incorrect.")

    # 9. VLM Trajectory Verification
    vlm_penalty = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if query_vlm and frames:
            vlm_res = query_vlm(prompt=_build_vlm_prompt(), images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                ui_interaction = parsed.get('ui_interaction_found', False)
                if not ui_interaction:
                    vlm_penalty = 30
                    feedback.append("PENALTY: VLM detected no substantial UI navigation (-30). Likely bypassed GUI.")
            else:
                logger.warning(f"VLM verification failed: {vlm_res.get('error')}")
    except Exception as e:
        logger.error(f"VLM check error: {e}")
        
    score = max(0, score - vlm_penalty)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }