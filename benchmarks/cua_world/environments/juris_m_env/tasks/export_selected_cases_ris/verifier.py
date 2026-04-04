#!/usr/bin/env python3
"""
Verifier for export_selected_cases_ris task.

Scoring Criteria:
1. File exists at /home/ga/Documents/landmark_cases.ris (15 pts)
2. File is a valid RIS file (contains TY tags) (15 pts)
3. File contains "Brown v. Board of Education" (20 pts)
4. File contains "Miranda v. Arizona" (20 pts)
5. File contains "Gideon v. Wainwright" (20 pts)
6. File contains exactly 3 items (no more, no less) (10 pts)

Anti-gaming:
- File must be created/modified after task start.
- If file contains unwanted items (e.g. Marbury, Obergefell), it indicates
  the user likely exported the whole collection/library, not selected items.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_selected_cases_ris(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the 3 specific cases were exported to RIS."""
    
    # Check for copy_from_env function
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from container
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
            "feedback": f"Could not retrieve export result: {e}. Did the task complete successfully?",
        }

    score = 0
    feedback = []
    
    # Extract result data
    file_exists = result.get("file_exists", False)
    file_created = result.get("file_created_during_task", False)
    ris_valid = result.get("ris_valid", False)
    item_count = result.get("item_count", 0)
    contains_brown = result.get("contains_brown", False)
    contains_miranda = result.get("contains_miranda", False)
    contains_gideon = result.get("contains_gideon", False)
    contains_unwanted = result.get("contains_unwanted", False)

    # Criterion 1: File Existence (15 pts)
    if file_exists:
        score += 15
        feedback.append("Output file exists (+15)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file 'landmark_cases.ris' not found in Documents folder.",
            "details": result
        }

    # Anti-gaming: Timestamp check
    if not file_created:
        feedback.append("WARNING: File timestamp predates task start. Anti-gaming check failed.")
        # We don't fail immediately but this is suspicious
        score = 0
        return {
            "passed": False,
            "score": 0,
            "feedback": "File was not created during this task session.",
            "details": result
        }

    # Criterion 2: Valid RIS format (15 pts)
    if ris_valid:
        score += 15
        feedback.append("File is valid RIS format (+15)")
    else:
        feedback.append("File is empty or not in RIS format (missing TY/ER tags)")

    # Criterion 3, 4, 5: Specific cases present (60 pts total)
    if contains_brown:
        score += 20
        feedback.append("Found 'Brown v. Board of Education' (+20)")
    else:
        feedback.append("Missing 'Brown v. Board of Education'")

    if contains_miranda:
        score += 20
        feedback.append("Found 'Miranda v. Arizona' (+20)")
    else:
        feedback.append("Missing 'Miranda v. Arizona'")
        
    if contains_gideon:
        score += 20
        feedback.append("Found 'Gideon v. Wainwright' (+20)")
    else:
        feedback.append("Missing 'Gideon v. Wainwright'")

    # Criterion 6: Exact item count (10 pts)
    if item_count == 3:
        score += 10
        feedback.append("Exactly 3 items exported (+10)")
    elif item_count > 3:
        feedback.append(f"Exported too many items ({item_count}). Only export the selected 3.")
        # Penalty for exporting extra items (likely "Select All" or collection export)
        # We cap the score deduction but it prevents perfect score
    else:
        feedback.append(f"Exported too few items ({item_count}). Expected 3.")

    # Check for unwanted items (indicates collection export instead of item selection)
    if contains_unwanted:
        feedback.append("File contains unrequested cases (e.g. Marbury, Obergefell). Please select ONLY the requested cases.")
        # Severe penalty for lack of selection precision if they just dumped the whole DB
        if score > 50:
            score -= 20 

    # Final score clamp
    score = max(0, min(100, score))
    passed = score >= 60 and contains_brown and contains_miranda and contains_gideon

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }