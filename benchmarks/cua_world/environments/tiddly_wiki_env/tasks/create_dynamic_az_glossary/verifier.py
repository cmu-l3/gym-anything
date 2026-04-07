#!/usr/bin/env python3
"""
Verifier for create_dynamic_az_glossary task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent's completion of a TiddlyWiki task.
The user asked the agent to create a dynamic "A-Z Glossary" that automatically groups terminology tiddlers by their first letter.

Examine the final screenshot of the TiddlyWiki interface.

Look at the rendered content of the "A-Z Glossary" tiddler (if visible).
A successful implementation will show:
1. Distinct letter headings (e.g., A, B, C, D, E, F)
2. Terms correctly listed under their corresponding letters (e.g., "Algorithm" and "API" under 'A', "Bandwidth" under 'B').
3. It should NOT just be a flat list of tags; it should be visibly grouped by alphabet letter.

Determine:
1. Is the "A-Z Glossary" tiddler visible and rendered?
2. Does the rendered view display grouped letters as headings/sections?
3. Are the terms (like Algorithm, API, Firewall) listed under these letter headings?

Respond ONLY in valid JSON format:
{
    "glossary_visible": true/false,
    "alphabetical_grouping_visible": true/false,
    "terms_listed_correctly": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def verify_az_glossary(traj, env_info, task_info):
    """
    Verify that the A-Z Glossary tiddler was created and dynamically lists the GlossaryTerms.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve output JSON from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Anti-gaming: Ensure the terms were not deleted
    terms_remaining = result.get('terms_remaining', 0)
    if terms_remaining < 10:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"FAIL: Required GlossaryTerm tiddlers were deleted (Found {terms_remaining}/10)"
        }

    # 2. Check if Glossary Tiddler exists (20 points)
    if result.get('glossary_found'):
        score += 20
        feedback_parts.append("Tiddler 'A-Z Glossary' found")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Tiddler 'A-Z Glossary' not found. Target not met."
        }

    # 3. Dynamic syntax usage (Anti-hardcoding) - 50 points total
    if result.get('has_list_widget'):
        score += 15
        feedback_parts.append("Used <$list> widget")
    else:
        feedback_parts.append("Missing <$list> widget (hardcoded list suspected)")

    if result.get('has_filter_attr'):
        score += 15
        feedback_parts.append("Used filter attribute")
        
    if result.get('has_tag_ref'):
        score += 10
        feedback_parts.append("Referenced GlossaryTerm tag dynamically")
        
    if result.get('has_dynamic_macro'):
        score += 10
        feedback_parts.append("Used prefix/variable operators for grouping")

    # 4. GUI interaction check (10 points)
    if result.get('gui_save_detected'):
        score += 10
        feedback_parts.append("Verified GUI save action in logs")

    # 5. VLM Visual Verification (20 points)
    vlm_score = 0
    try:
        from gym_anything.vlm import get_final_screenshot, query_vlm
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_response = query_vlm(images=[final_img], prompt=VLM_PROMPT)
            if vlm_response and vlm_response.get("success"):
                vlm_parsed = vlm_response.get("parsed", {})
                if vlm_parsed.get("glossary_visible"):
                    vlm_score += 5
                if vlm_parsed.get("alphabetical_grouping_visible"):
                    vlm_score += 10
                if vlm_parsed.get("terms_listed_correctly"):
                    vlm_score += 5
                feedback_parts.append(f"VLM visual verify: {vlm_score}/20 pts")
            else:
                feedback_parts.append("VLM visual verification failed to parse")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM visual verification skipped/errored")

    score += vlm_score
    
    # Require strong evidence of dynamic implementation to pass
    is_dynamic = result.get('has_list_widget') and result.get('has_filter_attr') and result.get('has_tag_ref')
    passed = score >= 65 and is_dynamic

    if not is_dynamic:
        feedback_parts.append("CRITICAL: Failed anti-hardcoding checks. Dynamic filters are required.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }