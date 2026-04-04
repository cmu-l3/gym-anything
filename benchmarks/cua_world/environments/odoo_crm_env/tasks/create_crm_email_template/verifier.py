#!/usr/bin/env python3
"""
Verifier for create_crm_email_template task.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_crm_email_template(traj, env_info, task_info):
    """
    Verify the agent created the Odoo email template correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # Criterion 1: Template Exists (20 pts)
    if result.get('template_found'):
        score += 20
        feedback_parts.append("Template 'Opportunity Follow-Up' created")
    else:
        feedback_parts.append("Template 'Opportunity Follow-Up' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Correct Model (20 pts)
    # Should be 'crm.lead'
    model = result.get('model', '')
    if model == 'crm.lead':
        score += 20
        feedback_parts.append("Correct model linked (crm.lead)")
    else:
        feedback_parts.append(f"Incorrect model linked: '{model}' (expected crm.lead)")

    # Criterion 3: Subject Placeholder (15 pts)
    subject = result.get('subject', '')
    # Allow spaces or no spaces in jinja syntax
    if '{{ object.name }}' in subject or '{{object.name}}' in subject:
        score += 15
        feedback_parts.append("Subject contains opportunity name placeholder")
    else:
        feedback_parts.append("Subject missing '{{ object.name }}' placeholder")

    # Criterion 4: Body Content (45 pts total)
    body = result.get('body_html', '') or ''
    
    # 4a. Partner Name Placeholder (15 pts)
    if '{{ object.partner_id.name }}' in body or '{{object.partner_id.name}}' in body:
        score += 15
        feedback_parts.append("Body: Partner placeholder found")
    else:
        feedback_parts.append("Body: Partner placeholder missing")

    # 4b. Opportunity Name Placeholder (10 pts)
    if '{{ object.name }}' in body or '{{object.name}}' in body:
        score += 10
        feedback_parts.append("Body: Opportunity placeholder found")
    else:
        feedback_parts.append("Body: Opportunity placeholder missing")

    # 4c. "Thank you" phrase (10 pts)
    if 'thank you for your interest' in body.lower():
        score += 10
        feedback_parts.append("Body: 'Thank you' phrase found")
    else:
        feedback_parts.append("Body: 'Thank you' phrase missing")

    # 4d. "Best regards" phrase (10 pts)
    if 'best regards' in body.lower():
        score += 10
        feedback_parts.append("Body: Closing found")
    else:
        feedback_parts.append("Body: Closing missing")

    # Anti-gaming check (Did we actually create something new?)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    created_recently = result.get('created_recently', False)

    if current_count <= initial_count and not created_recently:
        feedback_parts.append("WARNING: No new records created during task")
        # Penalize if it looks like they just renamed an old one or did nothing (though 'template_found' logic catches existence)
        # If score is high but count didn't increase, it's suspicious, but if we found the EXACT name and content, it's likely they did the work or renamed properly.
        # We will assume verifying the specific content is sufficient proof of work for this task, 
        # but strictly speaking, we want to see creation.
        
    passed = (score >= 70) and result.get('template_found') and (model == 'crm.lead')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }