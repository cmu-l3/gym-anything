#!/usr/bin/env python3
"""
Verifier for add_software_reference task.

Scoring Breakdown (100 pts total):
1. Item Created (20 pts): Item found in DB with correct type.
2. Metadata Correctness (35 pts):
   - Title matches (10 pts)
   - Version matches (10 pts)
   - Company/Place/URL/Date (15 pts total)
3. Creator Handling (45 pts):
   - Creator name is "R Core Team" (20 pts)
   - Creator mode is SINGLE FIELD (Institutional) (25 pts) -> Critical skill check

Pass Threshold: 80 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_software_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_software_reference_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Check Item Existence and Type (20 pts)
    if result.get("item_found"):
        item_type = result.get("item_type", "unknown")
        if item_type == "computerProgram":
            score += 20
            feedback.append("Item found with correct type 'Computer Program' (+20)")
        else:
            score += 10
            feedback.append(f"Item found but wrong type '{item_type}' (expected 'Computer Program') (+10)")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No item found with title starting 'R: A Language...'. Ensure you saved the item.",
            "details": result
        }

    metadata = result.get("metadata", {})
    creator = result.get("creator", {})
    
    # 2. Metadata Checks (35 pts)
    # Title (10)
    title = metadata.get("title", "")
    if "R: A Language and Environment for Statistical Computing" in title:
        score += 10
        feedback.append("Title correct (+10)")
    else:
        feedback.append(f"Title mismatch: '{title}'")
        
    # Version (10)
    version = metadata.get("version", "")
    if "4.3.0" in version:
        score += 10
        feedback.append("Version correct (+10)")
    else:
        feedback.append(f"Version mismatch or missing: '{version}'")
        
    # Other metadata (15 total)
    meta_score = 0
    if "R Foundation" in metadata.get("company", ""): meta_score += 5
    if "Vienna" in metadata.get("place", ""): meta_score += 5
    if "R-project.org" in metadata.get("url", ""): meta_score += 5
    # Date check (lenient)
    if "2023" in metadata.get("date", ""): meta_score += 0 # Bonus/Optional or included in above logic? 
    # Let's stick to the 15 pts split above
    
    score += meta_score
    feedback.append(f"Secondary metadata (Company, Place, URL) score: {meta_score}/15")

    # 3. Creator Handling (45 pts)
    # Name correctness (20)
    c_last = creator.get("lastName", "")
    c_first = creator.get("firstName", "")
    c_mode = creator.get("fieldMode", -1)
    
    full_string = creator.get("full_string", "")
    
    name_correct = False
    if "R Core Team" in full_string or ("Team" in c_last and "R Core" in c_first):
        score += 20
        name_correct = True
        feedback.append("Creator name correct (+20)")
    else:
        feedback.append(f"Creator name incorrect: got '{full_string}'")

    # Mode correctness (25) - CRITICAL
    # fieldMode: 1 = Single Field (Institutional), 0 = Two Fields (Personal)
    if name_correct:
        if c_mode == 1:
            score += 25
            feedback.append("Creator correctly set to Single Field/Institutional mode (+25)")
        else:
            feedback.append("Creator formatted as Person (First/Last) instead of Institution. Use the small field toggle icon. (-25)")
    
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }