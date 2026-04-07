#!/usr/bin/env python3
"""
Verifier for create_message_filter task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. Filter Rules File modified/created during task (10 pts)
2. Filter has correct name "Project Alpha Filter" (15 pts)
3. Filter condition accurately targets the subject (20 pts)
4. Filter action is Move to Folder (15 pts)
5. Filter targets the correct "ProjectAlpha" folder (5 pts)
6. ProjectAlpha folder was successfully created (15 pts)
7. Emails were moved matching the condition (15 pts)
8. Inbox email count reduction sanity check (5 pts)
9. VLM verification checks agent trajectories for the filter UI.
"""

import json
import tempfile
import os
import logging
import base64
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_message_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    rules_exists = result.get('rules_exists', False)
    rules_mtime = result.get('rules_mtime', 0)
    task_start = result.get('task_start', 0)
    folder_exists = result.get('folder_exists', False)
    project_alpha_emails = int(result.get('project_alpha_emails', 0))
    
    filter_name_correct = False
    
    # ---------------------------------------------------------
    # Rule Evaluation
    # ---------------------------------------------------------
    if rules_exists:
        if rules_mtime >= task_start:
            score += 10
            feedback_parts.append("Filter rules file modified")
        else:
            feedback_parts.append("Filter rules file exists but not modified during task")
            
        rules_content = ""
        b64_content = result.get('rules_content_b64', "")
        if b64_content:
            try:
                rules_content = base64.b64decode(b64_content).decode('utf-8', errors='ignore')
            except Exception as e:
                logger.warning(f"Error decoding base64: {e}")
                
        # 1. Check Name
        if re.search(r'name="Project Alpha Filter"', rules_content, re.IGNORECASE):
            score += 15
            filter_name_correct = True
            feedback_parts.append("Filter has correct name")
        else:
            feedback_parts.append("Filter name is incorrect or missing")
            
        # 2. Check Condition
        if re.search(r'condition=".*?subject,contains,Project Alpha.*?"', rules_content, re.IGNORECASE):
            score += 20
            feedback_parts.append("Filter has correct condition")
        elif "Project Alpha" in rules_content:
            score += 10
            feedback_parts.append("Filter condition partially correct")
            
        # 3. Check Action
        if re.search(r'action="Move to folder"', rules_content, re.IGNORECASE):
            score += 15
            feedback_parts.append("Filter has move action")
            
        # 4. Check Target Path
        if re.search(r'actionValue=".*?ProjectAlpha"', rules_content, re.IGNORECASE):
            score += 5
            feedback_parts.append("Filter targets correct folder")
    else:
        feedback_parts.append("No message filter rules found (msgFilterRules.dat missing)")
        
    # ---------------------------------------------------------
    # Folder and Sorting Evaluation
    # ---------------------------------------------------------
    if folder_exists:
        score += 15
        feedback_parts.append("ProjectAlpha folder exists")
        
        if project_alpha_emails > 0:
            score += 15
            feedback_parts.append(f"{project_alpha_emails} emails successfully sorted into folder")
        else:
            feedback_parts.append("No emails moved to ProjectAlpha folder")
    else:
        feedback_parts.append("ProjectAlpha folder not found")
        
    initial_inbox = result.get('initial_inbox_count', 0)
    current_inbox = result.get('current_inbox_count', 0)
    if project_alpha_emails > 0 and current_inbox < initial_inbox:
        score += 5
        feedback_parts.append("Inbox email count properly reduced")

    # ---------------------------------------------------------
    # VLM Evaluation (Trajectory Checks)
    # ---------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """You are analyzing screenshots from an agent creating an email message filter in Thunderbird.
Does the agent open the 'Message Filters' dialog UI and configure a filter condition at any point in these images?
Respond in JSON format:
{
    "filter_dialog_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief description"
}"""
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('filter_dialog_visible', False):
                feedback_parts.append("VLM verified filter dialog interaction")
            else:
                feedback_parts.append("VLM did not detect filter dialog")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        
    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    # The agent must at least get the filter created with the correct name and create the folder
    key_criteria_met = filter_name_correct and folder_exists
    passed = (score >= 60) and key_criteria_met
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }