#!/usr/bin/env python3
"""
Verifier for create_regulation_reference task.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_regulation_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the Regulation item was correctly created."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load expected values from metadata
    meta = task_info.get("metadata", {}).get("target_details", {})
    exp_title = meta.get("title", "Definitions")
    exp_agency = meta.get("agency", "Department of Health and Human Services")
    exp_code = meta.get("code", "C.F.R.")
    exp_vol = meta.get("volume", "45")
    exp_sect = meta.get("section", "160.103")
    exp_date = meta.get("date", "2002")

    # Retrieve result JSON
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
        return {"passed": False, "score": 0, "feedback": f"Export failed: {e}"}

    if not result.get("item_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No 'Regulation' item found in the library. Ensure you selected 'Regulation' as the item type.",
            "details": result
        }

    score = 0
    feedback = []
    fields = result.get("fields", {})
    
    # 1. Item Created (Base Score)
    score += 30
    feedback.append("Regulation item created (+30)")

    # 2. Check Agency (Legislative Body)
    agency = fields.get("agency") or ""
    if "health" in agency.lower() and "human services" in agency.lower():
        score += 15
        feedback.append("Legislative Body correct (+15)")
    else:
        feedback.append(f"Legislative Body mismatch. Expected '{exp_agency}', got '{agency}'")

    # 3. Check Code/Citation details
    # Code
    code = fields.get("code") or ""
    if "cfr" in code.lower().replace(".", ""):
        score += 10
        feedback.append("Code correct (+10)")
    else:
        feedback.append(f"Code mismatch. Expected '{exp_code}', got '{code}'")

    # Volume
    vol = str(fields.get("volume") or "")
    if vol == exp_vol:
        score += 5
        feedback.append("Volume correct (+5)")
    else:
        feedback.append(f"Volume mismatch. Expected '{exp_vol}', got '{vol}'")

    # Section
    sect = str(fields.get("section") or "")
    if exp_sect in sect:
        score += 10
        feedback.append("Section correct (+10)")
    else:
        feedback.append(f"Section mismatch. Expected '{exp_sect}', got '{sect}'")

    # 4. Check Date
    date = str(fields.get("date") or "")
    if exp_date in date:
        score += 10
        feedback.append("Date correct (+10)")
    else:
        feedback.append(f"Date mismatch. Expected '{exp_date}', got '{date}'")

    # 5. Anti-gaming (Time check)
    if result.get("created_during_task"):
        score += 20
        feedback.append("Item created during task window (+20)")
    else:
        feedback.append("Item appears to be old (pre-existing?)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }