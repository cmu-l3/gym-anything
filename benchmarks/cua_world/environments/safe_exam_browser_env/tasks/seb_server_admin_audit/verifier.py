#!/usr/bin/env python3
"""
Verifier for SEB Server Admin Audit task.
Evaluates if the agent accurately traversed the SEB Server interface, extracted entity data,
and formatted it into the requested text report.
"""

import os
import json
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_agent_report(content):
    """Parse the text report into a structured dictionary for evaluation."""
    sections = {
        'INSTITUTIONS': {'count': -1, 'items': []},
        'USER ACCOUNTS': {'count': -1, 'items': []},
        'LMS SETUPS': {'count': -1, 'items': []},
        'SEB EXAM CONFIGURATIONS': {'count': -1, 'items': []},
        'EXAMS': {'count': -1, 'items': []}
    }
    
    current_section = None
    lines = content.split('\n')
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # Check for section headers
        upper_line = line.upper()
        found_section = False
        for sec in sections.keys():
            if sec in upper_line and 'COUNT' not in upper_line:
                current_section = sec
                found_section = True
                break
                
        if found_section:
            continue
            
        if current_section:
            if upper_line.startswith('COUNT:'):
                try:
                    sections[current_section]['count'] = int(re.search(r'\d+', line).group())
                except Exception:
                    pass
            elif line.startswith('-'):
                # Extract item details (remove the bullet point)
                sections[current_section]['items'].append(line[1:].strip())
                
    return sections

def verify_seb_server_admin_audit(traj, env_info, task_info):
    """
    Verify the audit report contents against database ground truth.
    Includes trajectory verification via VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/seb_server_admin_audit_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Basic File Checks (15 points)
    if not result.get('file_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Audit report file was not found."
        }
    
    score += 10
    feedback.append("Report file exists.")
    
    if result.get('file_created_during_task'):
        score += 5
        feedback.append("File created during task session.")
    else:
        feedback.append("File modification time predates task start (possible anti-gaming violation).")

    # Parse Report
    content = result.get('file_content', '')
    parsed = parse_agent_report(content)
    gt = result.get('ground_truth', {})
    
    sections_correct = 0

    # 2. Institutions (15 points)
    gt_inst = gt.get('institutions', [])
    if parsed['INSTITUTIONS']['count'] == len(gt_inst):
        score += 10
        sections_correct += 1
        feedback.append(f"Institution count correct ({len(gt_inst)}).")
    else:
        feedback.append(f"Institution count incorrect (Expected {len(gt_inst)}, got {parsed['INSTITUTIONS']['count']}).")

    matched_inst = sum(1 for inst in gt_inst if any(inst.lower() in item.lower() for item in parsed['INSTITUTIONS']['items']))
    if gt_inst and (matched_inst / len(gt_inst)) >= 0.8:
        score += 5

    # 3. User Accounts (20 points)
    gt_users = gt.get('users', [])
    if parsed['USER ACCOUNTS']['count'] == len(gt_users):
        score += 10
        sections_correct += 1
        feedback.append(f"User count correct ({len(gt_users)}).")
    else:
        feedback.append(f"User count incorrect (Expected {len(gt_users)}, got {parsed['USER ACCOUNTS']['count']}).")
        
    matched_users = sum(1 for u in gt_users if any(u['username'].lower() in item.lower() for item in parsed['USER ACCOUNTS']['items']))
    if gt_users and (matched_users / len(gt_users)) >= 0.8:
        score += 10
        feedback.append("Usernames extracted correctly.")

    # 4. LMS Setups (15 points)
    gt_lms = gt.get('lms', [])
    if parsed['LMS SETUPS']['count'] == len(gt_lms):
        score += 10
        sections_correct += 1
        feedback.append(f"LMS count correct ({len(gt_lms)}).")
    else:
        feedback.append(f"LMS count incorrect (Expected {len(gt_lms)}, got {parsed['LMS SETUPS']['count']}).")

    matched_lms = sum(1 for lms in gt_lms if any(lms.lower() in item.lower() for item in parsed['LMS SETUPS']['items']))
    if gt_lms and (matched_lms / len(gt_lms)) >= 0.8:
        score += 5

    # 5. SEB Exam Configurations (15 points)
    gt_configs = gt.get('configs', [])
    if parsed['SEB EXAM CONFIGURATIONS']['count'] == len(gt_configs):
        score += 10
        sections_correct += 1
        feedback.append(f"Config count correct ({len(gt_configs)}).")
    else:
        feedback.append(f"Config count incorrect (Expected {len(gt_configs)}, got {parsed['SEB EXAM CONFIGURATIONS']['count']}).")
        
    matched_configs = sum(1 for c in gt_configs if any(c['name'].lower() in item.lower() for item in parsed['SEB EXAM CONFIGURATIONS']['items']))
    if gt_configs and (matched_configs / len(gt_configs)) >= 0.8:
        score += 5

    # 6. Exams (15 points)
    gt_exams = gt.get('exams', [])
    if parsed['EXAMS']['count'] == len(gt_exams):
        score += 10
        sections_correct += 1
        feedback.append(f"Exam count correct ({len(gt_exams)}).")
    else:
        feedback.append(f"Exam count incorrect (Expected {len(gt_exams)}, got {parsed['EXAMS']['count']}).")
        
    matched_exams = sum(1 for ex in gt_exams if any(ex.lower() in item.lower() for item in parsed['EXAMS']['items']))
    if gt_exams and (matched_exams / len(gt_exams)) >= 0.8:
        score += 5

    # 7. VLM Verification (5 points)
    # Check if trajectory proves agent actually navigated the SEB Server interface
    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "You are verifying if a user navigated through multiple sections of an administrative dashboard. "
            "Look at these screenshots taken during the session. "
            "1. Did the user navigate to at least two DIFFERENT sections (e.g., Institutions, User Accounts, LMS Setup, Exams)? "
            "2. Is there evidence of the user viewing tables or lists of items in the interface? "
            "Respond in JSON format: {\"navigated_multiple_sections\": true/false, \"viewed_lists\": true/false}"
        )
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_result and isinstance(vlm_result, dict):
            parsed_vlm = vlm_result.get("parsed", {})
            if parsed_vlm.get("navigated_multiple_sections") and parsed_vlm.get("viewed_lists"):
                score += 5
                feedback.append("VLM verified multi-section trajectory.")
            else:
                feedback.append("VLM did not detect multi-section navigation.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Default grant points if VLM fails to prevent pipeline breaks
        score += 5

    # Cap score at 100
    score = min(100, score)
    
    # Passing threshold: 60 points AND at least 3 out of 5 section counts must be correct
    passed = score >= 60 and sections_correct >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "sections_correct": sections_correct,
            "parsed_report": parsed
        }
    }