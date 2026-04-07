#!/usr/bin/env python3
"""Verifier for build_dynamic_reading_tracker task."""

import json
import tempfile
import os
import re
import logging
import sys

sys.path.insert(0, str(os.path.join(os.path.dirname(__file__), '..', '..')))
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("VLM utilities not available.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_hardcoded_values(text: str) -> bool:
    """Check if the text has hardcoded page numbers from the book seeds."""
    if not text:
        return False
    hardcoded_values = ['150', '387', '412', '896', '271', '45', '255']
    return any(val in text for val in hardcoded_values)


def verify_reading_tracker(traj, env_info, task_info):
    """Verify that the dynamic reading tracker was successfully built."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_books = metadata.get('books', [])

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

    macro_exists = result.get('macro_exists', False)
    dashboard_exists = result.get('dashboard_exists', False)
    macro_text = result.get('macro_text', '')
    dashboard_text = result.get('dashboard_text', '')
    rendered_html = result.get('rendered_html', '')

    # CRITERION 1: Macro Tiddler Created & Tagged (15 pts)
    if macro_exists:
        tags = result.get('macro_tags', '')
        if '$:/tags/Macro' in tags:
            score += 15
            feedback_parts.append("Macro tiddler created with correct tag")
        else:
            score += 5
            feedback_parts.append("Macro tiddler created but missing $:/tags/Macro tag")
    else:
        feedback_parts.append("FAIL: ProgressMacro tiddler not found")

    # CRITERION 2: Macro Definition Correct (20 pts)
    if macro_exists:
        has_define = r'\define' in macro_text and 'reading-progress' in macro_text
        has_progress = '<progress' in macro_text.lower()
        
        if has_define and has_progress:
            score += 20
            feedback_parts.append("Macro definition uses \\define and <progress>")
        elif has_define:
            score += 10
            feedback_parts.append("Macro definition exists but missing <progress> tag")
        elif has_progress:
            score += 5
            feedback_parts.append("Contains <progress> tag but no standard \\define syntax")

    # CRITERION 3: Dashboard Created with List Widget (15 pts)
    if dashboard_exists:
        if '<$list' in dashboard_text and ('tag[Book]' in dashboard_text or 'tag[book]' in dashboard_text):
            score += 15
            feedback_parts.append("Dashboard created with correct <$list> widget")
        elif '<$list' in dashboard_text:
            score += 10
            feedback_parts.append("Dashboard created with <$list> widget (tag filter might be wrong)")
        else:
            score += 5
            feedback_parts.append("Dashboard created but missing <$list> widget")
    else:
        feedback_parts.append("FAIL: Reading Dashboard tiddler not found")

    # CRITERION 4: Dynamic Data Binding - NO Hardcoding (20 pts)
    if dashboard_exists and macro_exists:
        macro_hardcoded = check_hardcoded_values(macro_text)
        dashboard_hardcoded = check_hardcoded_values(dashboard_text)

        if not macro_hardcoded and not dashboard_hardcoded:
            score += 20
            feedback_parts.append("Dynamic data binding confirmed (no hardcoded values in text)")
        else:
            feedback_parts.append("FAIL: Hardcoded values detected in macro or dashboard text!")

    # CRITERION 5: Rendered HTML Verification (30 pts)
    # This checks if the TiddlyWiki parser actually successfully generated the output.
    html_score = 0
    if rendered_html:
        found_bars = 0
        for book in expected_books:
            # Look for progress bars with specific value and max
            val = book['pages_read']
            max_val = book['total_pages']
            
            # The HTML could look like <progress max="387" value="150"> or <progress value="150" max="387">
            pattern1 = rf'<progress[^>]*value=["\']{val}["\'][^>]*max=["\']{max_val}["\']'
            pattern2 = rf'<progress[^>]*max=["\']{max_val}["\'][^>]*value=["\']{val}["\']'
            
            if re.search(pattern1, rendered_html, re.IGNORECASE) or re.search(pattern2, rendered_html, re.IGNORECASE):
                found_bars += 1
        
        if found_bars == len(expected_books):
            html_score = 30
            feedback_parts.append("All 4 progress bars correctly rendered in HTML")
        elif found_bars > 0:
            html_score = int(30 * (found_bars / len(expected_books)))
            feedback_parts.append(f"Rendered HTML contained {found_bars}/4 progress bars")
        else:
            feedback_parts.append("Rendered HTML did not contain correct <progress> elements")
    else:
        feedback_parts.append("Rendered HTML was empty or unavailable")
        
    score += html_score

    # Process Verification via Logs
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        feedback_parts.append("GUI interaction verified via server logs")

    # Final scoring
    key_criteria_met = dashboard_exists and macro_exists and html_score >= 15
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }