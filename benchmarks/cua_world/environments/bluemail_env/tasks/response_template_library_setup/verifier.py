#!/usr/bin/env python3
"""
Verifier for response_template_library_setup task.

Verifies:
1. Folder 'Response-Templates' creation (15 pts)
2. Presence of 3 specific master templates (15 pts count + 30 pts content)
3. Preservation of 'Template: Acknowledgment' master (20 pts)
4. Sending of a reply using the template content (20 pts)
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_response_template_library_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_templates = metadata.get('templates', [])
    
    # 1. Retrieve Result JSON
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
    feedback = []
    
    # 2. Verify Folder Creation (15 pts)
    if result.get("folder_created"):
        score += 15
        feedback.append(f"Folder '{result['folder_name_found']}' created.")
    else:
        feedback.append("Failed: 'Response-Templates' folder not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 3. Verify Draft Count (15 pts)
    draft_count = result.get("draft_count", 0)
    if draft_count >= 3:
        score += 15
        feedback.append(f"Folder contains {draft_count} drafts (>=3).")
    else:
        # Partial credit
        score += (draft_count * 5)
        feedback.append(f"Folder contains only {draft_count} drafts (expected 3).")

    # 4. Verify Content (30 pts - 10 per template found)
    # We check if the specific subjects exist in the templates found
    templates_found = result.get("templates_found", [])
    found_subjects = [t.get("subject", "") for t in templates_found]
    
    ack_template_present = False
    
    for tmpl in expected_templates:
        # Check if any found template matches this expected template
        # We check subject containment
        match = False
        for found in templates_found:
            if tmpl["subject"].lower() in found.get("subject", "").lower():
                match = True
                # Check for Ack template specifically for later criterion
                if "acknowledgment" in tmpl["subject"].lower():
                    ack_template_present = True
                break
        
        if match:
            score += 10
            feedback.append(f"Found template: {tmpl['subject']}")
        else:
            feedback.append(f"Missing template: {tmpl['subject']}")

    # 5. Verify Preservation of 'Acknowledgment' Template (20 pts)
    # This is the "Don't just send the draft" check
    if ack_template_present:
        score += 20
        feedback.append("Master template 'Acknowledgment' preserved in library.")
    else:
        feedback.append("Failed: 'Acknowledgment' template missing! (Did you send the master draft instead of copying it?)")

    # 6. Verify Reply Sent (20 pts)
    if result.get("reply_sent"):
        score += 20
        feedback.append("Reply sent successfully with template content.")
    else:
        feedback.append("Failed: No sent reply found containing the acknowledgment text.")

    # Calculate final result
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }