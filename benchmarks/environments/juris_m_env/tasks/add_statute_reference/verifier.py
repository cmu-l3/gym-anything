#!/usr/bin/env python3
"""
Verifier for add_statute_reference task.

Criteria:
1. Item exists with "Civil Rights Act" in a field (40 pts)
2. Item type is 'statute' (20 pts)
3. Specific metadata fields match expected values (40 pts total)
   - Code: U.S.C. (5)
   - Code Number: 42 (5)
   - Section: 2000e (5)
   - Date Enacted: 1964 (5)
   - Public Law No: 88-352 (10)
   - History: 78 Stat (5)
   - Session: 2d (5)

Pass threshold: 60 points
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_statute_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load metadata expectations
    meta = task_info.get("metadata", {})
    
    # Retrieve result file
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_statute_reference_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve result file: {e}"
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    score = 0
    feedback = []
    
    item_found = result.get("item_found", False)
    item_data = result.get("item", {})
    
    # Criterion 1: Item Created (40 pts)
    if item_found:
        score += 40
        feedback.append("Item 'Civil Rights Act' found in library (+40)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No item found with 'Civil Rights Act'. Ensure you saved the item.",
            "details": result
        }

    # Criterion 2: Item Type (20 pts)
    # Check if type_name is statute OR is_statute flag is true
    is_statute = item_data.get("is_statute", False)
    type_name = item_data.get("type_name", "unknown")
    
    if is_statute or type_name.lower() == "statute":
        score += 20
        feedback.append("Item type is correctly set to Statute (+20)")
    else:
        feedback.append(f"Incorrect item type: {type_name} (Expected: Statute)")

    # Criterion 3: Field Verification (40 pts total)
    # Mapping of expected keys to possible DB field names (Jurism internal names can vary)
    # Common mappings:
    # Code -> code, codePages
    # Code Number -> codeNumber, codeVolume
    # Section -> section, pages
    # Date Enacted -> dateEnacted, date
    # Public Law No -> publicLawNumber, number
    # Session -> session
    # History -> history
    
    field_scores = [
        ("Code", ["code", "codePages"], meta.get("expected_code", "U.S.C."), 5),
        ("Code Number", ["codeNumber", "codeVolume"], meta.get("expected_code_number", "42"), 5),
        ("Section", ["section", "pages"], meta.get("expected_section", "2000e"), 5),
        ("Date", ["dateEnacted", "date"], "1964", 5), # partial match for date
        ("Public Law No", ["publicLawNumber", "number"], "88-352", 10),
        ("History", ["history"], "78 Stat", 5),
        ("Session", ["session"], "2d", 5)
    ]
    
    for label, keys, expected, pts in field_scores:
        # Find actual value in any of the potential keys
        actual = ""
        for k in keys:
            if k in item_data and item_data[k]:
                actual = str(item_data[k])
                break
        
        # Check match (case-insensitive, partial for longer fields)
        if expected.lower() in actual.lower():
            score += pts
            feedback.append(f"{label} correct (+{pts})")
        else:
            if actual:
                feedback.append(f"{label} mismatch (Expected: {expected}, Got: {actual})")
            else:
                feedback.append(f"{label} missing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }