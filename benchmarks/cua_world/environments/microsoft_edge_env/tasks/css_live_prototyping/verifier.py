#!/usr/bin/env python3
"""
Verifier for CSS Live Prototyping task.
Verifies:
1. Agent visited example.com (History)
2. Agent created CSS file with correct rules (File content)
3. Agent created a screenshot of the mockup (File existence)
4. Visual verification of the mockup screenshot using VLM
"""

import json
import logging
import os
import re
import tempfile
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_css_live_prototyping(traj, env_info, task_info):
    """
    Verify css_live_prototyping task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    css_reqs = metadata.get('css_requirements', {})

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: History (10 pts) ---
    if result.get('history', {}).get('visited_example_com', False):
        score += 10
        feedback_parts.append("Visited target site (10/10)")
    else:
        feedback_parts.append("Did not visit example.com (0/10)")

    # --- Criterion 2: CSS File Content (45 pts) ---
    css_file = result.get('css_file', {})
    if css_file.get('exists') and css_file.get('created_during_task'):
        score += 5 # Base points for file creation
        content = css_file.get('content', '').lower()
        
        # Helper to check rules regex
        def check_rule(name, regex_pattern, points):
            if re.search(regex_pattern, content):
                return points, f"{name} correct"
            return 0, f"{name} missing/incorrect"

        # Body BG
        bg_patterns = "|".join([re.escape(c) for c in css_reqs.get('body_bg', ['aliceblue'])])
        p1, f1 = check_rule("Body Background", r"body\s*{[^}]*background(-color)?:\s*(" + bg_patterns + ")", 10)
        
        # H1
        h1_color_pats = "|".join([re.escape(c) for c in css_reqs.get('h1_color', ['darkblue'])])
        p2, f2 = check_rule("H1 Color", r"h1\s*{[^}]*color:\s*(" + h1_color_pats + ")", 5)
        p3, f3 = check_rule("H1 Align", r"h1\s*{[^}]*text-align:\s*center", 5)
        p4, f4 = check_rule("H1 Decor", r"h1\s*{[^}]*text-decoration:\s*underline", 5)
        
        # P Font
        p5, f5 = check_rule("P Font", r"p\s*{[^}]*font-family:\s*[^;]*monospace", 5)
        
        # Link
        a_bg_pats = "|".join([re.escape(c) for c in css_reqs.get('a_bg', ['magenta'])])
        a_col_pats = "|".join([re.escape(c) for c in css_reqs.get('a_color', ['white'])])
        p6, f6 = check_rule("Link BG", r"a\s*{[^}]*background(-color)?:\s*(" + a_bg_pats + ")", 5)
        p7, f7 = check_rule("Link Color", r"a\s*{[^}]*color:\s*(" + a_col_pats + ")", 5)

        css_score = p1 + p2 + p3 + p4 + p5 + p6 + p7
        score += css_score
        
        # Simplify feedback
        missing_rules = []
        if p1 == 0: missing_rules.append("Body BG")
        if p2 == 0 or p3 == 0 or p4 == 0: missing_rules.append("H1 Styles")
        if p5 == 0: missing_rules.append("P Font")
        if p6 == 0 or p7 == 0: missing_rules.append("Link Styles")
        
        if not missing_rules:
            feedback_parts.append("CSS file content perfect (45/45)")
        else:
            feedback_parts.append(f"CSS file valid but missing: {', '.join(missing_rules)} ({css_score + 5}/45)")
            
    else:
        feedback_parts.append("CSS file not found or not created during task (0/45)")

    # --- Criterion 3: Visual Verification (Mockup or Final Screen) (45 pts) ---
    # We prefer the user's mockup.png, but if missing, check final screen
    mockup_info = result.get('mockup_file', {})
    image_to_check = None
    
    if mockup_info.get('exists') and mockup_info.get('created_during_task'):
        # Copy the mockup from container to local temp for VLM
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(mockup_info['path_for_verification'], temp_img.name)
            image_to_check = temp_img.name
            score += 5 # Points for creating the file
        except Exception as e:
            logger.error(f"Failed to copy mockup image: {e}")
    else:
        feedback_parts.append("Mockup screenshot file missing (-5 pts)")
        # Fallback to final system screenshot if mockup file missing
        # This allows partial credit if they did the work but failed to save the screenshot file correctly
        final_path = result.get('final_screenshot_path')
        if final_path:
            try:
                temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                copy_from_env(final_path, temp_img.name)
                image_to_check = temp_img.name
            except:
                pass

    if image_to_check:
        prompt = (
            "Look at this webpage screenshot of 'Example Domain'. "
            "Check for these specific visual styles:\n"
            "1. Is the page background a light blue color?\n"
            "2. Is the main heading 'Example Domain' centered, underlined, and dark blue?\n"
            "3. Is the paragraph text in a monospace/code font?\n"
            "4. Does the 'More information' link have a bright magenta/pink background with white text?\n"
            "Answer 'YES' only if at least 3 of these 4 stylistic changes are clearly visible."
        )
        
        vlm_res = query_vlm(
            prompt=prompt,
            images=[image_to_check]
        )
        
        # Clean up temp image
        if os.path.exists(image_to_check):
            os.unlink(image_to_check)
            
        if vlm_res.get('success'):
            ans = vlm_res.get('answer', '').upper()
            if "YES" in ans:
                score += 40
                feedback_parts.append("Visual verification passed (40/40)")
            else:
                feedback_parts.append(f"Visual verification failed: {vlm_res.get('answer')} (0/40)")
        else:
            feedback_parts.append("VLM verification error (0/40)")
    else:
        feedback_parts.append("No screenshots available for verification (0/40)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }