#!/usr/bin/env python3
"""Verifier for build_automated_standup_generator task."""

import json
import tempfile
import os

def verify_automated_standup_generator(traj, env_info, task_info):
    """Verify that the standup generator tool was created and used successfully."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/standup_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Template Created (15 pts)
    template_text = result.get('template_text', '')
    if result.get('template_exists'):
        score += 5
        if '! Yesterday' in template_text and '! Today' in template_text and '! Blockers' in template_text:
            score += 10
            feedback_parts.append("Template created with correct headers")
        else:
            feedback_parts.append("Template missing some headers")
    else:
        feedback_parts.append("Standup Template not found")

    # 2. Dashboard UI (25 pts)
    dashboard_text = result.get('dashboard_text', '')
    if result.get('dashboard_exists'):
        score += 5
        if '<$button' in dashboard_text and 'tm-new-tiddler' in dashboard_text:
            score += 20
            feedback_parts.append("Dashboard button with tm-new-tiddler logic found")
        else:
            feedback_parts.append("Dashboard missing button or tm-new-tiddler logic")
            
        # 3. Dynamic Title Logic (15 pts)
        if '<<now' in dashboard_text or '<$macrocall' in dashboard_text:
            score += 15
            feedback_parts.append("Dynamic title logic found")
        else:
            feedback_parts.append("Missing dynamic title logic")
            
        # 4. List Widget Included (15 pts)
        if '<$list' in dashboard_text and ('tag[Standup]' in dashboard_text or 'tag[standup]' in dashboard_text):
            score += 15
            feedback_parts.append("List widget filtering for Standup tag found")
        else:
            feedback_parts.append("Missing list widget for Standup tag")
    else:
        feedback_parts.append("Scrum Dashboard not found")

    # 5. Tool Successfully Used (30 pts)
    if result.get('today_standup_exists'):
        score += 5
        today_text = result.get('today_standup_text', '')
        today_tags = result.get('today_standup_tags', '')
        today_title = result.get('today_standup_title', '')
        expected_today_str = result.get('expected_today_str', '')
        
        # Check Title against dynamic date
        if expected_today_str in today_title:
            score += 5
        else:
            feedback_parts.append(f"Note title '{today_title}' might not contain today's date '{expected_today_str}'")
        
        # Check Tag assignment mechanism
        if 'Standup' in today_tags or 'standup' in today_tags.lower():
            score += 5
            
        # Check Boilerplate Headers insertion
        if '! Yesterday' in today_text and '! Today' in today_text and '! Blockers' in today_text:
            score += 5
            
        # Check Specific text addition requirement
        if 'Configured the automated standup generator' in today_text:
            score += 10
            feedback_parts.append("Successfully used the tool to create today's standup note")
        else:
            feedback_parts.append("Today's note missing the required specific text")
    else:
        feedback_parts.append("Today's standup note not generated")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }