#!/usr/bin/env python3
"""
Verifier for relate_cases task.

Verification Strategy:
1. Database Check (Primary):
   - Reads exported JSON which contains status of specific item relations.
   - Checks for 3 specific pairs of bidirectional links.
   - 30 points per pair.

2. Anti-Gaming:
   - Checks if relation count actually increased during task.
   - 10 points for evidence of activity.

3. VLM Verification (Visual):
   - Checks trajectory/screenshots to see if the "Related" tab was interacted with.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

# Import VLM utils if available in environment
try:
    from gym_anything.vlm import get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_relate_cases(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that legal cases were correctly related in Jurism."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result. Did the task complete successfully? Error: {e}"
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Runtime error during verification: {result['error']}"}

    score = 0
    feedback_lines = []
    
    # 2. Verify Specific Relations (90 Points)
    pairs = result.get("pairs", {})
    
    # Pair 1: Brown <-> Tinker
    p1 = pairs.get("brown_tinker", {})
    if p1.get("complete"):
        score += 30
        feedback_lines.append("✓ Brown v. Board <-> Tinker v. Des Moines (Linked)")
    elif p1.get("forward") or p1.get("reverse"):
        score += 15
        feedback_lines.append("⚠ Brown v. Board <-> Tinker v. Des Moines (Partially Linked - One way only)")
    else:
        feedback_lines.append("✗ Brown v. Board <-> Tinker v. Des Moines (Not Linked)")

    # Pair 2: Gideon <-> Miranda
    p2 = pairs.get("gideon_miranda", {})
    if p2.get("complete"):
        score += 30
        feedback_lines.append("✓ Gideon v. Wainwright <-> Miranda v. Arizona (Linked)")
    elif p2.get("forward") or p2.get("reverse"):
        score += 15
        feedback_lines.append("⚠ Gideon v. Wainwright <-> Miranda v. Arizona (Partially Linked - One way only)")
    else:
        feedback_lines.append("✗ Gideon v. Wainwright <-> Miranda v. Arizona (Not Linked)")

    # Pair 3: NYT <-> Tinker
    p3 = pairs.get("nyt_tinker", {})
    if p3.get("complete"):
        score += 30
        feedback_lines.append("✓ NYT v. Sullivan <-> Tinker v. Des Moines (Linked)")
    elif p3.get("forward") or p3.get("reverse"):
        score += 15
        feedback_lines.append("⚠ NYT v. Sullivan <-> Tinker v. Des Moines (Partially Linked - One way only)")
    else:
        feedback_lines.append("✗ NYT v. Sullivan <-> Tinker v. Des Moines (Not Linked)")

    # 3. Anti-Gaming / Activity Check (10 Points)
    relations_added = result.get("relations_added", 0)
    if relations_added >= 1:
        score += 10
    else:
        feedback_lines.append("No new relations found in database.")

    # 4. Optional VLM Verification (Bonus/Confirmation)
    # We use this to confirm UI interaction if database check is borderline or to provide better feedback
    if VLM_AVAILABLE:
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_resp = query_vlm(
                images=[final_img],
                prompt="Is the 'Related' tab visible in the right-hand pane of this application window? It should show a list of related items."
            )
            if "yes" in str(vlm_resp).lower():
                feedback_lines.append("(Visual check confirmed 'Related' tab is active)")

    passed = score >= 70  # Requires at least 2 full pairs + activity, or 3 partials + activity
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
        "details": result
    }