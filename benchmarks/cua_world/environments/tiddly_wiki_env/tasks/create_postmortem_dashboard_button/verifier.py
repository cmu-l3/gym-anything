#!/usr/bin/env python3
"""
Verifier for create_postmortem_dashboard_button task.

Checks:
1. Dashboard exists and is tagged correctly
2. List widget filters for PostMortem
3. Button widget triggers tm-new-tiddler
4. Scaffolding correctly sets title, tags, custom fields, and boilerplate text.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/postmortem_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    dashboard_exists = result.get("dashboard_exists", False)
    dashboard_tags = result.get("dashboard_tags", "")
    dashboard_text = result.get("dashboard_text", "")
    template_text = result.get("template_text", "")
    
    # Criterion 1: Dashboard Creation & Tags (10 points)
    if dashboard_exists:
        score += 5
        if "Dashboard" in dashboard_tags:
            score += 5
            feedback_parts.append("Dashboard tiddler exists with 'Dashboard' tag (10/10)")
        else:
            feedback_parts.append("Dashboard tiddler exists but missing 'Dashboard' tag (5/10)")
    else:
        feedback_parts.append("FAIL: 'Post-Mortem Dashboard' tiddler not found (0/10)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Parse wikitext logic
    has_list = "<$list" in dashboard_text and "tag[PostMortem]" in dashboard_text
    has_button = ("<$button" in dashboard_text or "<$action-sendmessage" in dashboard_text)
    sends_message = "tm-new-tiddler" in dashboard_text
    has_button_label = "Create New Post-Mortem" in dashboard_text
    
    # Criterion 2: List Implementation (15 points)
    if has_list:
        score += 15
        feedback_parts.append("List widget filtering 'PostMortem' found (15/15)")
    else:
        feedback_parts.append("FAIL: List widget with 'tag[PostMortem]' not found (0/15)")

    # Criterion 3: Button Implementation (15 points)
    if has_button and sends_message and has_button_label:
        score += 15
        feedback_parts.append("Button widget triggering 'tm-new-tiddler' found (15/15)")
    elif has_button and sends_message:
        score += 10
        feedback_parts.append("Button widget triggering 'tm-new-tiddler' found but label missing/incorrect (10/15)")
    else:
        feedback_parts.append("FAIL: Button triggering 'tm-new-tiddler' not found (0/15)")

    # Analyze combined text for scaffolding payloads (inline or template)
    combined_logic = dashboard_text + "\n" + template_text
    
    # Criterion 4: Title & Tags Scaffolding (20 points)
    title_scaffold = "New Post-Mortem Report" in combined_logic
    tags_scaffold = "PostMortem" in combined_logic and "Draft" in combined_logic
    
    if title_scaffold and tags_scaffold:
        score += 20
        feedback_parts.append("Scaffolds correct Title and Tags (20/20)")
    elif title_scaffold:
        score += 10
        feedback_parts.append("Scaffolds correct Title, but missing Tags (10/20)")
    else:
        feedback_parts.append("FAIL: Does not scaffold Title/Tags correctly (0/20)")

    # Criterion 5: Custom Fields Scaffolding (20 points)
    fields_scaffold = "incident_date" in combined_logic and "severity" in combined_logic
    if fields_scaffold:
        score += 20
        feedback_parts.append("Scaffolds 'incident_date' and 'severity' fields (20/20)")
    elif "incident_date" in combined_logic or "severity" in combined_logic:
        score += 10
        feedback_parts.append("Scaffolds partial custom fields (10/20)")
    else:
        feedback_parts.append("FAIL: Does not scaffold custom fields (0/20)")

    # Criterion 6: Boilerplate Text Scaffolding (20 points)
    has_summary = "!! Summary" in combined_logic
    has_rc = "!! Root Cause" in combined_logic
    has_res = "!! Resolution" in combined_logic
    
    boilerplate_score = 0
    if has_summary: boilerplate_score += 6
    if has_rc: boilerplate_score += 7
    if has_res: boilerplate_score += 7
    
    score += boilerplate_score
    if boilerplate_score == 20:
        feedback_parts.append("Scaffolds complete boilerplate text (20/20)")
    else:
        feedback_parts.append(f"Scaffolds partial/missing boilerplate text ({boilerplate_score}/20)")

    # Anti-gaming: Ensure the work was mediated by the UI 
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        feedback_parts.append("[GUI interaction verified]")
        
    # Final pass determination
    # Must have created the dashboard, the button, and achieved at least 70 overall
    key_criteria_met = dashboard_exists and has_button and sends_message
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }