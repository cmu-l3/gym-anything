#!/usr/bin/env python3
"""
Verifier for configure_case_short_titles task.

Scoring:
- Brown v. Board set to "Brown": 30 pts
- Miranda v. Arizona set to "Miranda": 30 pts
- Obergefell v. Hodges set to "Obergefell": 30 pts
- Items were modified during task session: 10 pts (anti-gaming)

Total: 100 pts.
Pass threshold: 90 pts.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_case_short_titles(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that short titles were correctly set for the three target cases."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON
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
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error during verification export: {result['error']}"}

    cases_data = result.get("cases_data", [])
    if not cases_data:
        return {"passed": False, "score": 0, "feedback": "No case data found in verification result."}

    score = 0
    feedback = []
    
    # Track modification bonus
    modified_count = 0
    total_modified_needed = 0

    for case in cases_data:
        target_name = case.get("target_name", "Unknown")
        expected = case.get("expected_short", "")
        actual = case.get("actual_short", "")
        found = case.get("found", False)
        modified = case.get("modified_during_task", False)

        if not found:
            feedback.append(f"❌ '{target_name}' not found in library.")
            continue

        total_modified_needed += 1
        
        # Check value (case-sensitive usually, but let's be lenient on whitespace)
        if actual and actual.strip() == expected:
            score += 30
            feedback.append(f"✅ '{target_name}': Short Title correctly set to '{actual}'.")
            if modified:
                modified_count += 1
        elif actual:
            feedback.append(f"⚠️ '{target_name}': Short Title is '{actual}', expected '{expected}'.")
        else:
            feedback.append(f"❌ '{target_name}': Short Title is empty.")

    # Anti-gaming bonus: At least one item was actually modified during the session
    # This prevents passing if the environment was pre-configured (though setup script clears them)
    if modified_count >= 1:
        score += 10
        feedback.append("✅ Timestamp check passed (items modified during session).")
    elif score > 0:
        feedback.append("⚠️ Timestamp check failed (items not modified during session).")

    # Pass threshold
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": result
    }