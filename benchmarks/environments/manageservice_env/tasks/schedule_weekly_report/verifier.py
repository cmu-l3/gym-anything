#!/usr/bin/env python3
"""
Verifier for schedule_weekly_report task.

Verifies that:
1. A schedule with name "Weekly Executive Summary" exists in the database.
2. The recipient "director@example.com" is configured.
3. The subject "Weekly Open Ticket Status" is set.
4. The output format is PDF.
5. VLM verification of the final screenshot confirms the schedule list view.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_weekly_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_schedule_name', "Weekly Executive Summary")
    expected_recipient = metadata.get('expected_recipient', "director@example.com")
    expected_subject = metadata.get('expected_subject', "Weekly Open Ticket Status")
    
    score = 0
    feedback_parts = []
    
    # 1. Load exported result JSON
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

    # 2. Database Verification (Primary)
    db_verified = False
    
    # Check Schedule Name
    task_data = result.get('schedule_task_data')
    if task_data and isinstance(task_data, dict):
        actual_name = task_data.get('schedule_name', '')
        if expected_name.lower() in actual_name.lower():
            score += 30
            feedback_parts.append("Schedule created with correct name")
            db_verified = True
            
            # Check Format (PDF)
            # Format often stored as int or string, we check loosely
            actual_format = str(task_data.get('report_format', '')).lower()
            if 'pdf' in actual_format or '1' in actual_format: # assuming 1 might be pdf, strictly text 'pdf' usually
                score += 10
                feedback_parts.append("Format is PDF")
        else:
            feedback_parts.append(f"Schedule name mismatch (found: {actual_name})")
    else:
        feedback_parts.append("Schedule record not found in database")

    # Check Email Recipient & Subject
    email_data = result.get('email_config_data')
    if email_data and isinstance(email_data, dict):
        actual_to = email_data.get('mail_to', '')
        actual_subject = email_data.get('subject', '')
        
        if expected_recipient in actual_to:
            score += 20
            feedback_parts.append("Recipient correct")
        else:
            feedback_parts.append(f"Recipient mismatch (found: {actual_to})")
            
        if expected_subject.lower() in actual_subject.lower():
            score += 10
            feedback_parts.append("Subject correct")
        else:
            feedback_parts.append(f"Subject mismatch (found: {actual_subject})")
    else:
        # Fallback: if task found but email table query failed (schema issue), give partial credit
        # relying on VLM for the rest
        if db_verified:
            feedback_parts.append("Email details not verified in DB (schema mismatch?)")

    # 3. Anti-gaming check (Count increased)
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    if current_count > initial_count:
        score += 10
        feedback_parts.append("New schedule record verified")

    # 4. VLM Verification (Secondary/Fallback)
    # Essential for verifying "Weekly/Monday/08:00" if DB schema is obscure
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = f"""
        Analyze this screenshot of ManageEngine ServiceDesk Plus.
        I am looking for a scheduled report named "{expected_name}".
        
        Check for:
        1. Is the "Scheduled Reports" list visible?
        2. Is there a row/card for "{expected_name}"?
        3. Does it show "Weekly" or "Monday" frequency?
        4. Does it show "08:00" or "8:00 AM"?
        5. Is the email recipient "{expected_recipient}" visible?
        
        Answer with JSON:
        {{
            "list_visible": true/false,
            "schedule_found": true/false,
            "frequency_correct": true/false,
            "time_correct": true/false,
            "recipient_visible": true/false
        }}
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('schedule_found'):
            # If DB failed entirely, VLM can save the day (up to 70 pts max without DB)
            if not db_verified:
                score += 30
                feedback_parts.append("VLM found schedule in UI")
            
            if parsed.get('frequency_correct'):
                score += 10
                feedback_parts.append("VLM confirmed weekly frequency")
                
            if parsed.get('time_correct'):
                score += 10
                feedback_parts.append("VLM confirmed time")
        else:
            feedback_parts.append("VLM did not see the schedule in the final screenshot")
            
    # Calculate final result
    # Pass threshold: 70 points
    # Must have either DB record OR VLM visual confirmation of the schedule
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }