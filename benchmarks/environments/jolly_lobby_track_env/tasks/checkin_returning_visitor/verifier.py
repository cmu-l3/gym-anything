#!/usr/bin/env python3
"""
Verifier for checkin_returning_visitor task.
Uses VLM to verify the visible state of the visitor log and checks file timestamps.
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying a "Returning Visitor Check-in" task in Jolly Lobby Track software.

The user was supposed to:
1. Import a visitor list (containing Sarah Chen).
2. Check in 'Sarah Chen' (Company: Deloitte).
3. Set Host to 'Michael Torres'.
4. Set Purpose to 'Contractor'.

Look at the screenshot and answer the following:
1. Is 'Sarah Chen' visible in the visitor list?
2. Is her status 'Signed In' (or is she in the active visitors list)?
3. Is the Company listed as 'Deloitte'?
4. Is the Host listed as 'Michael Torres'?
5. Is the Purpose listed as 'Contractor'?

Provide your assessment in JSON format:
{
  "sarah_chen_visible": true/false,
  "status_signed_in": true/false,
  "company_is_deloitte": true/false,
  "host_is_michael_torres": true/false,
  "purpose_is_contractor": true/false,
  "confidence": "high/medium/low",
  "reasoning": "..."
}
"""

def verify_checkin_returning_visitor(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the task using VLM for screen content and file timestamps for anti-gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Load technical evidence (file timestamps)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            tech_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task evidence: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db_modified = tech_result.get("db_modified", False)
    db_size_changed = tech_result.get("db_size_changed", False)

    # 2. VLM Verification
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available"}

    vlm_out = query_vlm(prompt=VLM_PROMPT, image=final_screenshot)
    
    if not vlm_out.get("success"):
        return {"passed": False, "score": 0, "feedback": f"VLM analysis failed: {vlm_out.get('error')}"}
    
    parsed = vlm_out.get("parsed", {})
    logger.info(f"VLM Analysis: {parsed}")

    # 3. Scoring
    score = 0
    feedback_items = []

    # Technical Check (20 pts)
    if db_modified or db_size_changed:
        score += 20
        feedback_items.append("Database updated successfully")
    else:
        feedback_items.append("Warning: Database file was not modified (Action might not be saved)")

    # Visual Checks (80 pts)
    if parsed.get("sarah_chen_visible", False):
        score += 20
        feedback_items.append("Sarah Chen found in list")
    else:
        feedback_items.append("Sarah Chen NOT found in list")

    if parsed.get("status_signed_in", False):
        score += 20
        feedback_items.append("Status: Signed In")
    else:
        feedback_items.append("Status check failed (not signed in?)")

    # Details
    details_score = 0
    if parsed.get("host_is_michael_torres", False):
        details_score += 20
        feedback_items.append("Host correct (Michael Torres)")
    else:
        feedback_items.append("Host incorrect or not visible")

    if parsed.get("purpose_is_contractor", False):
        details_score += 20
        feedback_items.append("Purpose correct (Contractor)")
    else:
        feedback_items.append("Purpose incorrect or not visible")
    
    score += details_score

    # Company check (bonus/tie-breaker, usually implied by finding Sarah)
    if parsed.get("company_is_deloitte", False):
        feedback_items.append("Company verified")

    # Pass logic
    passed = score >= 80  # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_items),
        "details": parsed
    }