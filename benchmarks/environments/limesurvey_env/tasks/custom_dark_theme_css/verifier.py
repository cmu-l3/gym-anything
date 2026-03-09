#!/usr/bin/env python3
"""
Verifier for custom_dark_theme_css task.

Criteria:
1. Survey 'Night Shift Worker Experience' must exist.
2. Theme 'NightShiftDark' must exist in filesystem.
3. Survey must have 'NightShiftDark' assigned as template.
4. custom.css must contain correct background-color (#121212) and color (#e0e0e0).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_dark_theme(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # Metadata
    expected_bg = task_info.get('metadata', {}).get('expected_bg_color', '#121212')
    expected_fg = task_info.get('metadata', {}).get('expected_text_color', '#e0e0e0')
    expected_theme = task_info.get('metadata', {}).get('expected_theme_name', 'NightShiftDark')

    # Criterion A: Survey Exists (10 pts)
    if result.get('survey_found', False):
        score += 10
        feedback.append("Survey 'Night Shift Worker Experience' found.")
    else:
        feedback.append("Survey 'Night Shift Worker Experience' NOT found.")

    # Criterion B: Theme Exists (30 pts)
    if result.get('theme_exists', False):
        score += 30
        feedback.append(f"Theme '{expected_theme}' directory created.")
    else:
        feedback.append(f"Theme '{expected_theme}' directory NOT found.")
        # If theme doesn't exist, we can't check CSS or assignment meaningfully
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion C: CSS Content (40 pts total)
    css_content = result.get('css_content', '')
    
    # Normalize CSS for easier checking (remove spaces, lowercase)
    # We look for "background-color:#121212" pattern variants
    
    # Check Background Color (20 pts)
    # Regex allows for spaces, optional semicolon, case insensitive
    bg_regex = re.compile(r'background-color\s*:\s*#121212', re.IGNORECASE)
    if bg_regex.search(css_content):
        score += 20
        feedback.append(f"CSS background-color set to {expected_bg}.")
    else:
        feedback.append(f"CSS background-color NOT correct (expected {expected_bg}).")

    # Check Text Color (20 pts)
    fg_regex = re.compile(r'color\s*:\s*#e0e0e0', re.IGNORECASE)
    if fg_regex.search(css_content):
        score += 20
        feedback.append(f"CSS text color set to {expected_fg}.")
    else:
        feedback.append(f"CSS text color NOT correct (expected {expected_fg}).")

    # Criterion D: Theme Assigned to Survey (20 pts)
    assigned_template = result.get('assigned_template', '')
    if assigned_template == expected_theme:
        score += 20
        feedback.append(f"Survey is using the '{expected_theme}' theme.")
    else:
        feedback.append(f"Survey template is '{assigned_template}', expected '{expected_theme}'.")

    # 3. Final Result
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }