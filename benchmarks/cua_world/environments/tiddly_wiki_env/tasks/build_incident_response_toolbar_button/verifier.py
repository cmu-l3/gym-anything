#!/usr/bin/env python3
"""Verifier for build_incident_response_toolbar_button task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_incident_button(traj, env_info, task_info):
    """
    Verify that the user correctly created the Incident Template
    and the corresponding Toolbar Button with appropriate system tags and widgets.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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
    
    task_start = result.get('task_start', 0)
    template_mtime = result.get('template_mtime', 0)
    button_mtime = result.get('button_mtime', 0)
    
    # Check for anti-gaming (making sure files were touched during the task)
    if template_mtime > 0 and template_mtime < task_start - 10:
        feedback_parts.append("WARNING: Template was created before task started.")
    if button_mtime > 0 and button_mtime < task_start - 10:
        feedback_parts.append("WARNING: Button was created before task started.")

    # 1. Evaluate Template (Total 40 points)
    template_exists = result.get('template_exists', False)
    if template_exists:
        score += 10
        feedback_parts.append("Incident Template exists")
        
        # Check Tags & Fields (20 points)
        t_tags = result.get('template_tags', '')
        t_status = result.get('template_status', '')
        t_severity = result.get('template_severity', '')
        
        fields_score = 0
        if "Security Incident" in t_tags:
            fields_score += 10
        if t_status.lower() == "open":
            fields_score += 5
        if t_severity.lower() == "triage":
            fields_score += 5
            
        score += fields_score
        feedback_parts.append(f"Template fields: {fields_score}/20 pts")
        
        # Check Body Content (10 points)
        t_text = result.get('template_text', '')
        headers_found = 0
        if "# Incident Summary" in t_text:
            headers_found += 1
        if "# Indicators of Compromise (IoCs)" in t_text:
            headers_found += 1
        if "# Remediation Actions" in t_text:
            headers_found += 1
            
        if headers_found == 3:
            score += 10
            feedback_parts.append("Template body format correct")
        elif headers_found > 0:
            score += 5
            feedback_parts.append(f"Template body partially correct ({headers_found}/3 headers)")
        else:
            feedback_parts.append("Template body missing required headings")
            
    else:
        feedback_parts.append("FAIL: Incident Template not found")

    # 2. Evaluate Button (Total 60 points)
    button_exists = result.get('button_exists', False)
    if button_exists:
        score += 10
        feedback_parts.append("Button tiddler exists")
        
        # Check UI System Tag (15 points)
        b_tags = result.get('button_tags', '')
        if "$:/tags/PageControls" in b_tags:
            score += 15
            feedback_parts.append("Button tagged for PageControls")
        else:
            feedback_parts.append("FAIL: Button missing $:/tags/PageControls system tag")
            
        # Check Widgets in Text (35 points total)
        b_text = result.get('button_text', '')
        
        has_button = bool(re.search(r'<\$button\b', b_text))
        has_action = bool(re.search(r'<\$action-sendmessage\b', b_text))
        
        # We need to allow single quotes, double quotes, or unquoted attributes (though spaces would break unquoted)
        has_msg = bool(re.search(r'\$message=["\']?tm-new-tiddler["\']?', b_text))
        has_param = bool(re.search(r'\$param=["\']?Incident Template["\']?', b_text))
        has_title_attr = bool(re.search(r'\btitle=["\']?New Security Incident["\']?', b_text))
        
        widget_pts = 0
        if has_button:
            widget_pts += 10
        if has_action and has_msg:
            widget_pts += 10
        if has_param:
            widget_pts += 10
        if has_title_attr:
            widget_pts += 5
            
        score += widget_pts
        feedback_parts.append(f"Button widget architecture: {widget_pts}/35 pts")
        
    else:
        feedback_parts.append("FAIL: Button tiddler not found ($:/custom/buttons/NewIncident)")

    # Anti-gaming via server log (to ensure they didn't just dump files but used the tool, though file writing is acceptable in TW if Node syncs it)
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        feedback_parts.append("GUI interaction verified via logs")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }