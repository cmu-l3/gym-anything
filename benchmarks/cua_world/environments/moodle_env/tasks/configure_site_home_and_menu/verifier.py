#!/usr/bin/env python3
"""Verifier for Configure Site Home and Menu task in Moodle."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_site_home_and_menu(traj, env_info, task_info):
    """
    Verify site identity and custom menu configuration.

    Scoring (100 points):
    - Site Full Name Updated (20 pts)
    - Site Short Name Updated (20 pts)
    - Front Page Summary Updated (20 pts)
    - Menu: Library Link present (15 pts)
    - Menu: Student Services present (10 pts)
    - Menu: Sub-items hierarchy correct (15 pts)

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fullname = metadata.get('expected_fullname', 'Springfield Technical College LMS')
    expected_shortname = metadata.get('expected_shortname', 'STC Moodle')
    expected_summary_part = metadata.get('expected_summary_part', 'Welcome to the official learning platform for Springfield Technical College')
    
    # Expected menu parts
    menu_lib = metadata.get('menu_item_library', 'Library|http://library.example.edu')
    menu_parent = metadata.get('menu_item_parent', 'Student Services')
    menu_child1 = metadata.get('menu_item_child_1', '-Help Desk|http://help.example.edu')
    menu_child2 = metadata.get('menu_item_child_2', '-Calendar|http://calendar.example.edu')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/site_config_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Verify Site Full Name (20 pts)
        actual_fullname = result.get('fullname', '').strip()
        if actual_fullname.lower() == expected_fullname.lower():
            score += 20
            subscores['fullname'] = True
            feedback_parts.append("Full Name correct")
        else:
            subscores['fullname'] = False
            feedback_parts.append(f"Full Name mismatch: '{actual_fullname}'")

        # 2. Verify Site Short Name (20 pts)
        actual_shortname = result.get('shortname', '').strip()
        if actual_shortname == expected_shortname:
            score += 20
            subscores['shortname'] = True
            feedback_parts.append("Short Name correct")
        else:
            subscores['shortname'] = False
            feedback_parts.append(f"Short Name mismatch: '{actual_shortname}'")

        # 3. Verify Summary (20 pts)
        actual_summary = result.get('summary', '')
        # Remove HTML tags for checking text content if necessary, or just simple check
        # Moodle summary is HTML, so we check if the string is contained
        clean_summary = re.sub(r'<[^>]+>', '', actual_summary).strip()
        if expected_summary_part.lower() in clean_summary.lower() or expected_summary_part.lower() in actual_summary.lower():
            score += 20
            subscores['summary'] = True
            feedback_parts.append("Summary text found")
        else:
            subscores['summary'] = False
            feedback_parts.append("Summary text not found")

        # 4. Verify Menu Configuration
        actual_menu = result.get('custommenuitems', '')
        # Normalize newlines
        actual_menu_norm = actual_menu.replace('\\n', '\n').replace('\r', '')

        # Check Library link (15 pts)
        if menu_lib in actual_menu_norm:
            score += 15
            subscores['menu_lib'] = True
            feedback_parts.append("Library menu item found")
        else:
            subscores['menu_lib'] = False
            feedback_parts.append("Library menu item missing/incorrect")

        # Check Parent Item (10 pts)
        if menu_parent in actual_menu_norm:
            score += 10
            subscores['menu_parent'] = True
            feedback_parts.append("Student Services parent item found")
        else:
            subscores['menu_parent'] = False
            feedback_parts.append("Student Services menu item missing")

        # Check Children Items (15 pts) - check strict syntax with hyphen
        if menu_child1 in actual_menu_norm and menu_child2 in actual_menu_norm:
            score += 15
            subscores['menu_children'] = True
            feedback_parts.append("Dropdown sub-items found")
        else:
            subscores['menu_children'] = False
            feedback_parts.append("Dropdown sub-items missing or formatted incorrectly")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export_result.sh failed"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Result file contains invalid JSON"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}