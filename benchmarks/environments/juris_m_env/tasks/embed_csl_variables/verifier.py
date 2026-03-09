#!/usr/bin/env python3
"""
Verifier for embed_csl_variables task.

Verification Strategy:
1. Retrieve exported JSON result containing the "Extra" field content for the 3 target items.
2. Check if the content matches the required CSL variable strings.

Scoring (100 points total):
- Holmes ("The Path of the Law"): 'original-date: 1897' (30 pts)
- Monaghan ("Constitutional Fact Review"): 'DOI: 10.2307/1122547' (30 pts)
- Poe ("The Due Process Clause..."): 'citation-key: poe_torts_1971' (30 pts)
- Data integrity (items exist): 10 pts

Pass threshold: 70 points (Must get at least 2/3 fields correct + data integrity)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_embed_csl_variables(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that CSL variables were correctly embedded in the 'Extra' fields."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/embed_csl_variables_result.json", temp.name)
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
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {result['error']}"}

    items_found = result.get("items_found", {})
    score = 0
    feedback = []

    # 1. Verify Holmes (The Path of the Law)
    holmes = items_found.get("holmes", {})
    if holmes.get("found"):
        extra = holmes.get("extra_content", "") or ""
        # Check for specific string, case-insensitive logic for keys, exact for values usually preferable
        # but users might add spaces.
        if "original-date: 1897" in extra:
            score += 30
            feedback.append("Holmes: 'original-date' correctly added (+30)")
        elif "original-date" in extra and "1897" in extra:
            # Partial credit if formatting is slightly off but content is there
            score += 20
            feedback.append("Holmes: Content present but formatting inexact (+20)")
        else:
            feedback.append(f"Holmes: Expected 'original-date: 1897', got '{extra}'")
    else:
        feedback.append("Holmes: Item not found in library (-30)")

    # 2. Verify Monaghan (Constitutional Fact Review)
    monaghan = items_found.get("monaghan", {})
    if monaghan.get("found"):
        extra = monaghan.get("extra_content", "") or ""
        expected_doi = "10.2307/1122547"
        if f"DOI: {expected_doi}" in extra:
            score += 30
            feedback.append("Monaghan: DOI correctly added (+30)")
        elif "DOI" in extra and expected_doi in extra:
            score += 20
            feedback.append("Monaghan: DOI present but formatting inexact (+20)")
        else:
            feedback.append(f"Monaghan: Expected 'DOI: {expected_doi}', got '{extra}'")
    else:
        feedback.append("Monaghan: Item not found in library (-30)")

    # 3. Verify Poe (Due Process Clause...)
    poe = items_found.get("poe", {})
    if poe.get("found"):
        extra = poe.get("extra_content", "") or ""
        expected_key = "poe_torts_1971"
        if f"citation-key: {expected_key}" in extra:
            score += 30
            feedback.append("Poe: Citation key correctly added (+30)")
        elif "citation-key" in extra and expected_key in extra:
            score += 20
            feedback.append("Poe: Key present but formatting inexact (+20)")
        else:
            feedback.append(f"Poe: Expected 'citation-key: {expected_key}', got '{extra}'")
    else:
        feedback.append("Poe: Item not found in library (-30)")

    # 4. Data Integrity Bonus
    # If all items were found, give 10 points
    if holmes.get("found") and monaghan.get("found") and poe.get("found"):
        score += 10
        feedback.append("Data integrity check passed: All items preserved (+10)")
    else:
        feedback.append("Data integrity check failed: Some items missing")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": result,
    }