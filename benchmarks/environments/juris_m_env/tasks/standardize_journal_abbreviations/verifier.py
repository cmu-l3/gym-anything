#!/usr/bin/env python3
"""
Verifier for standardize_journal_abbreviations task.

Verification strategy:
1. Load result JSON exported from the environment.
2. For each target item, check if the "Journal Abbr" field matches expectations.
3. Verify that items were modified during the task window (anti-gaming).

Scoring (100 points total):
- 30 pts per correct abbreviation (3 items = 90 pts)
- 10 pts for valid timestamps (evidence of active work)

Pass threshold: 90 points (Accuracy is paramount for citations)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_standardize_journal_abbreviations(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load metadata for expected values
    metadata = task_info.get("metadata", {})
    targets = metadata.get("targets", [])
    
    if not targets:
        # Fallback defaults if metadata missing
        targets = [
            {"title": "The Path of the Law", "expected_abbr": "Harv. L. Rev."},
            {"title": "Constitutional Fact Review", "expected_abbr": "Colum. L. Rev."},
            {"title": "The Due Process Clause and the Substantive Law of Torts", "expected_abbr": "Yale L.J."}
        ]

    # Retrieve result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/standardize_journal_abbreviations_result.json", temp.name)
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
        return {"passed": False, "score": 0, "feedback": f"Error in export script: {result['error']}"}

    items_res = result.get("items", {})
    
    score = 0
    feedback = []
    timestamp_points_awarded = False
    
    for target in targets:
        title = target["title"]
        expected = target["expected_abbr"]
        
        item_data = items_res.get(title)
        
        if not item_data:
            feedback.append(f"❌ Item '{title}' not found in verification data.")
            continue
            
        if not item_data.get("found"):
            feedback.append(f"❌ Item '{title}' not found in library.")
            continue
            
        actual = item_data.get("abbr_value")
        
        # Check Value
        if actual == expected:
            score += 30
            feedback.append(f"✅ '{title}': Correct ({actual})")
        elif actual is None:
             feedback.append(f"❌ '{title}': Field is empty (Expected: {expected})")
        else:
             feedback.append(f"❌ '{title}': Incorrect value '{actual}' (Expected: {expected})")
             
        # Check Timestamp (Global 10pts if at least one item modified during task)
        if item_data.get("modified_during_task") and not timestamp_points_awarded:
            score += 10
            timestamp_points_awarded = True
            feedback.append("✅ Detected modification during task window (+10)")

    # Construct final feedback
    final_feedback = " | ".join(feedback)
    passed = (score >= 90) # Must get all abbreviations correct to pass

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback,
        "details": result
    }