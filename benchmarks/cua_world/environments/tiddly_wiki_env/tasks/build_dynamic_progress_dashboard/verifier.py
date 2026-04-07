#!/usr/bin/env python3
"""Verifier for build_dynamic_progress_dashboard task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dynamic_dashboard(traj, env_info, task_info):
    """Verify that the dynamic dashboard calculates progress and filters tasks correctly."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dashboard_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    stylesheet_exists = result.get('stylesheet_exists', False)
    dashboard_exists = result.get('dashboard_exists', False)
    initial_html = result.get('initial_html', '')
    mutated_html = result.get('mutated_html', '')

    # Criterion 1: Stylesheet Setup (10 pts)
    if stylesheet_exists and result.get('is_tagged_stylesheet'):
        css = result.get('stylesheet_content', '')
        if '.progress-bg' in css and '.progress-bar' in css:
            score += 10
            feedback_parts.append("Stylesheet correctly configured")
        else:
            score += 5
            feedback_parts.append("Stylesheet exists but missing required CSS classes")
    else:
        feedback_parts.append("FAIL: ProgressBarStyles tiddler missing or incorrectly tagged")

    # Criterion 2: Dashboard Exists (10 pts)
    if dashboard_exists and result.get('is_tagged_dashboard'):
        score += 10
        feedback_parts.append("Dashboard correctly created and tagged")
    else:
        feedback_parts.append("FAIL: Dashboard tiddler missing or incorrectly tagged")
        # Critical failure, no point checking math if it doesn't exist
        if not dashboard_exists:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Helper function to check rendered HTML for correct math
    def check_percentages(html, expectations):
        passed_levels = 0
        for level, expected_pct in expectations.items():
            # Check text "Completion: X%"
            text_match = re.search(rf'Completion:\s*{expected_pct}(?:\.0*)?%', html, re.IGNORECASE)
            # Check style "width: X%;"
            # Limit scope to around the level title to avoid false positives across the document
            level_block = html.split(level)[-1][:500] if level in html else ""
            style_match = re.search(rf'width:\s*{expected_pct}(?:\.0*)?%', level_block, re.IGNORECASE)
            
            if text_match and style_match:
                passed_levels += 1
        return passed_levels

    # Criterion 3: Initial Math Calculation (20 pts)
    initial_expected = {
        "Clockwork Tower": 25,
        "Crystal Caverns": 50,
        "Magma Core": 20,
        "Neon City": 0,
        "Whispering Woods": 100
    }
    
    if initial_html:
        initial_passed = check_percentages(initial_html, initial_expected)
        if initial_passed == 5:
            score += 20
            feedback_parts.append("Initial math calculations correct (5/5 levels)")
        elif initial_passed > 0:
            score += (initial_passed * 4)
            feedback_parts.append(f"Initial math calculations partially correct ({initial_passed}/5 levels)")
        else:
            feedback_parts.append("FAIL: Initial math calculations incorrect or missing")

        # Criterion 4: Remaining Tasks Filter (20 pts)
        # Clockwork Tower remaining: Rig elevator platform (in-progress), Sound design (todo), Lighting (todo)
        # Should NOT show: Model main gears (done)
        has_remaining = re.search(r'Rig elevator platform.*?\(in-progress\)', initial_html, re.IGNORECASE)
        has_done_accidentally = re.search(r'Model main gears.*?\(done\)', initial_html, re.IGNORECASE)
        has_remaining_header = "**Remaining Tasks:**" in initial_html or "Remaining Tasks" in initial_html
        
        if has_remaining and not has_done_accidentally and has_remaining_header:
            score += 20
            feedback_parts.append("Remaining tasks correctly filtered")
        elif has_remaining:
            score += 10
            feedback_parts.append("Remaining tasks shown but filter logic imperfect")
        else:
            feedback_parts.append("FAIL: Remaining tasks list missing or formatted incorrectly")
    else:
        feedback_parts.append("FAIL: Could not parse rendered Dashboard HTML")

    # Criterion 5: Dynamic Reaction / Anti-Gaming (40 pts)
    # The setup script mutates: Clockwork Tower (+1 done -> 50%), Neon City (+1 done -> 50%)
    mutated_expected = {
        "Clockwork Tower": 50,
        "Neon City": 50
    }
    
    dynamic_points = 0
    if mutated_html:
        mutated_passed = check_percentages(mutated_html, mutated_expected)
        if mutated_passed == 2:
            dynamic_points = 40
            feedback_parts.append("Dynamic math verified (reacted to state changes)")
        elif mutated_passed == 1:
            dynamic_points = 20
            feedback_parts.append("Dynamic math partially verified (reacted to 1 state change)")
        else:
            feedback_parts.append("FAIL: Math did not update when task states changed (Hardcoded detected)")
    
    score += dynamic_points

    # Final Evaluation
    # Note: To pass, the agent MUST have at least partial dynamic reaction (preventing hardcoded text bypasses)
    passed = score >= 70 and dynamic_points >= 20
    
    if passed:
        feedback_parts.insert(0, "SUCCESS")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }