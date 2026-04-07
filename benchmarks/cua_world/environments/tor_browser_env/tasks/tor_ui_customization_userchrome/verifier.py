#!/usr/bin/env python3
"""
Verifier for tor_ui_customization_userchrome task.

Verifies that the agent properly customized the Tor Browser UI by:
1. Enabling legacy stylesheets in about:config
2. Creating a 'chrome' directory in the active profile
3. Creating a 'userChrome.css' file with specific UI hiding rules
4. Ensuring the CSS file was created AFTER the task started
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tor_ui_customization(traj, env_info, task_info):
    """
    Scoring (100 points):
    - File Creation Timestamp (Anti-gaming) - 10 pts [REQUIRED GATE]
    - Preference Enabled (legacy stylesheets) - 25 pts
    - Directory Structure ('chrome' exists) - 15 pts
    - CSS: Comment & New Tab hiding - 20 pts
    - CSS: Extensions hiding & Tab Color - 30 pts

    Pass threshold: 75+ points WITH the anti-gaming gate passing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found or malformed: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Task Result: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []

    # Check if profile was found at all
    if not result.get("profile_found", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Tor Browser profile directory not found. Browser may not have been started."
        }

    # Criterion 1: Anti-gaming / File existence (10 pts) [GATE]
    file_exists = result.get("css_file_exists", False)
    file_is_new = result.get("css_file_is_new", False)
    
    if not file_exists:
        feedback_parts.append("FAIL: userChrome.css does not exist (0/10)")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) + " - Crucial file missing."
        }
        
    if file_is_new:
        score += 10
        feedback_parts.append("userChrome.css created during task (10/10)")
    else:
        feedback_parts.append("FAIL: userChrome.css existed before task start (Anti-gaming gate failed)")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Preference Enabled (25 pts)
    if result.get("pref_enabled", False):
        score += 25
        feedback_parts.append("legacyUserProfileCustomizations enabled (25/25)")
    else:
        feedback_parts.append("legacyUserProfileCustomizations NOT enabled in about:config (0/25)")

    # Criterion 3: Directory Structure (15 pts)
    if result.get("chrome_dir_exists", False):
        score += 15
        feedback_parts.append("'chrome' directory created (15/15)")
    else:
        feedback_parts.append("'chrome' directory missing (0/15)")

    # Criterion 4: CSS Comment & New Tab button rule (20 pts)
    has_comment = result.get("has_comment", False)
    has_newtab = result.get("has_newtab_hidden", False)
    
    if has_comment and has_newtab:
        score += 20
        feedback_parts.append("CSS Comment & New Tab rule correct (20/20)")
    elif has_newtab:
        score += 15
        feedback_parts.append("New Tab rule present, comment missing (15/20)")
    else:
        feedback_parts.append("New Tab hiding rule missing (0/20)")

    # Criterion 5: CSS Extensions rule & Tab Background Color (30 pts)
    has_ext = result.get("has_extensions_hidden", False)
    has_tab_bg = result.get("has_tab_bg_color", False)
    
    if has_ext and has_tab_bg:
        score += 30
        feedback_parts.append("CSS Extensions rule & Tab Background correct (30/30)")
    elif has_ext or has_tab_bg:
        score += 15
        feedback_parts.append("Partial CSS Extensions/Tab rules (15/30)")
    else:
        feedback_parts.append("Extensions and Tab Background rules missing (0/30)")

    # Evaluate Pass/Fail
    passed = score >= 75 and file_is_new

    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback
    }