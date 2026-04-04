#!/usr/bin/env python3
"""
Verifier for fix_author_field_structure task.

Verification Strategy:
1. Read the exported JSON which contains the state of the authors for the two target items.
2. For "Constitutional Fact Review":
   - fieldMode should be 0 (Two-field)
   - lastName should be "Monaghan"
   - firstName should be "Henry P."
3. For "The Due Process Clause...":
   - fieldMode should be 0 (Two-field)
   - lastName should be "Poe"
   - firstName should be "Ronald D."

Scoring:
- 50 points per correct author (25 for correct mode, 25 for correct name parsing)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_author_field_structure(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that author fields have been corrected to two-field mode."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
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
            "feedback": f"Could not retrieve export result: {e}",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback = []
    
    targets = result.get("targets", [])
    
    # Map for easy lookup
    target_map = {t.get("id"): t for t in targets}
    
    # 1. Verify Monaghan
    monaghan = target_map.get("monaghan")
    if not monaghan or not monaghan.get("found"):
        feedback.append("Item 'Constitutional Fact Review' not found in library.")
    elif not monaghan.get("has_creator"):
        feedback.append("Item 'Constitutional Fact Review' has no author.")
    else:
        # Check Mode
        if monaghan.get("field_mode") == 0:
            score += 25
            feedback.append("Monaghan: Correctly switched to Two-field mode (+25).")
            
            # Check Name Split
            fname = monaghan.get("first_name", "").strip()
            lname = monaghan.get("last_name", "").strip()
            
            if lname == "Monaghan" and fname == "Henry P.":
                score += 25
                feedback.append("Monaghan: Name correctly split (+25).")
            else:
                feedback.append(f"Monaghan: Name split incorrect (Found First: '{fname}', Last: '{lname}'). Expected First: 'Henry P.', Last: 'Monaghan'.")
        else:
            feedback.append("Monaghan: Still in Single-field mode (should be Two-field).")

    # 2. Verify Poe
    poe = target_map.get("poe")
    if not poe or not poe.get("found"):
        feedback.append("Item 'The Due Process Clause' not found in library.")
    elif not poe.get("has_creator"):
        feedback.append("Item 'The Due Process Clause' has no author.")
    else:
        # Check Mode
        if poe.get("field_mode") == 0:
            score += 25
            feedback.append("Poe: Correctly switched to Two-field mode (+25).")
            
            # Check Name Split
            fname = poe.get("first_name", "").strip()
            lname = poe.get("last_name", "").strip()
            
            if lname == "Poe" and fname == "Ronald D.":
                score += 25
                feedback.append("Poe: Name correctly split (+25).")
            else:
                feedback.append(f"Poe: Name split incorrect (Found First: '{fname}', Last: '{lname}'). Expected First: 'Ronald D.', Last: 'Poe'.")
        else:
            feedback.append("Poe: Still in Single-field mode (should be Two-field).")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }