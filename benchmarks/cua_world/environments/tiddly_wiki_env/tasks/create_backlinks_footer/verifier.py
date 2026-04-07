#!/usr/bin/env python3
"""
Verifier for create_backlinks_footer task.

Evaluates:
1. ViewTemplate Tag creation (20 pts)
2. Proper filter use (`backlinks[]`) (30 pts)
3. Link rendering (`<$link`) (20 pts)
4. Conditional Display Logic (orphan notes must not show empty headings) (30 pts)
"""

import json
import os
import tempfile
import re
import logging
from typing import Dict, Any

sys_path_added = False
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_backlinks_footer(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve exported result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    template_found = result.get("template_found", False)
    content = result.get("template_content", "")
    linked_html = result.get("linked_note_html", "")
    orphan_html = result.get("orphan_note_html", "")
    gui_save = result.get("gui_save_detected", False)

    # 1. Check if Template exists with correct Tag (20 pts)
    if template_found:
        score += 20
        feedback.append("ViewTemplate tiddler created successfully.")
    else:
        feedback.append("FAIL: No new ViewTemplate tiddler was found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Check for `backlinks[]` filter operator (30 pts)
    # We check the wikitext to ensure they used the correct TiddlyWiki mechanism
    if "backlinks[" in content:
        score += 30
        feedback.append("Used `backlinks[]` filter operator.")
    elif "backlinks" in content:
        score += 15
        feedback.append("Partial: Mentioned backlinks but missing operator syntax.")
    else:
        feedback.append("FAIL: Did not use the `backlinks[]` operator.")

    # 3. Check for link rendering (20 pts)
    if "<$link" in content or "[[<currentTiddler>]]" in content or "[[<" in content:
        score += 20
        feedback.append("Used link widgets/syntax for rendering.")
    else:
        feedback.append("FAIL: Did not use `<$link>` widget to render clickable items.")

    # 4. Check Conditional Logic (30 pts)
    # They should not render a heading if there are no backlinks.
    # We test this dynamically by analyzing the rendered HTML of "Orphan Note" vs "Evergreen Notes"
    
    # Extract likely heading strings from their wikitext to look for in the HTML
    # E.g., !! Backlinks -> "Backlinks"
    heading_match = re.search(r'^!+\s*(.+)$|<h[1-6]>(.+)</h[1-6]>', content, re.MULTILINE)
    heading_text = None
    if heading_match:
        heading_text = heading_match.group(1) or heading_match.group(2)
        heading_text = heading_text.strip()
    
    if heading_text and len(heading_text) > 2:
        # If the heading text is visible in the heavily linked note, but NOT in the orphan note, they nailed it!
        in_linked = heading_text.lower() in linked_html.lower()
        in_orphan = heading_text.lower() in orphan_html.lower()
        
        if in_linked and not in_orphan:
            score += 30
            feedback.append("Conditional logic verified: Heading hidden on orphan notes.")
        elif in_linked and in_orphan:
            feedback.append(f"FAIL: Conditional logic missing. Heading '{heading_text}' appears on orphan notes.")
        else:
            # Fallback static analysis if HTML checking is inconclusive
            _static_conditional_check()
    else:
        _static_conditional_check()

    def _static_conditional_check():
        nonlocal score, feedback
        # Static check for `limit[1]` or `<$reveal` guarding the block
        if "limit[1]" in content or "<$reveal" in content:
            score += 20  # Partial points for static match if dynamic fails/inconclusive
            feedback.append("Found conditional logic markers (limit[1] or reveal) in wikitext.")
        else:
            feedback.append("FAIL: Could not verify conditional logic. Orphan notes may incorrectly show the Backlinks heading.")

    # Anti-gaming: Ensure the agent interacted with the GUI
    if not gui_save:
        feedback.append("WARNING: No GUI save detected. Possible hardcoded file creation.")
        score = max(0, score - 20)

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "template_found": template_found,
            "gui_save_detected": gui_save
        }
    }