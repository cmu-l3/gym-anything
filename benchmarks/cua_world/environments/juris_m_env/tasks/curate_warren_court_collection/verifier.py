#!/usr/bin/env python3
"""
Verifier for curate_warren_court_collection task.

Scoring Criteria:
1. Collection Creation (20 pts): "Warren Court" collection exists.
2. Item Count (20 pts): Contains exactly 5 items.
3. Inclusion (30 pts): Contains the 5 correct cases (6 pts each).
4. Exclusion (30 pts): Contains no incorrect items (penalty for each wrong item).
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_curate_warren_court_collection(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result from container
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
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {e}"
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Database error: {result['error']}"}

    # Metadata / Ground Truth
    target_cases = [
        "Brown v. Board of Education",
        "Gideon v. Wainwright",
        "New York Times Co. v. Sullivan",
        "Miranda v. Arizona",
        "Tinker v. Des Moines"
    ]
    # Note: DB might have full "Tinker v. Des Moines Independent Community School District"
    # We will use substring matching for robustness.

    score = 0
    feedback = []
    
    # 1. Collection Exists (20 pts)
    if result.get("collection_exists"):
        score += 20
        feedback.append("Collection 'Warren Court' created (+20)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Collection 'Warren Court' not found. You must create a new collection with this exact name.",
            "details": result
        }

    items = result.get("items", [])
    item_count = len(items)
    
    # 2. Correct Item Count (20 pts)
    # We award full points for exactly 5, partial for close.
    if item_count == 5:
        score += 20
        feedback.append("Collection contains exactly 5 items (+20)")
    elif item_count > 0:
        # Partial credit? No, count must be exact to encourage filtering, 
        # but let's check content first to see if they just missed one.
        feedback.append(f"Collection contains {item_count} items (expected 5)")
    else:
        feedback.append("Collection is empty")

    # 3. Inclusion & Exclusion (60 pts total distributed)
    # Strategy: +6 for each correct case, -10 for each wrong case (min 0)
    
    inclusion_score = 0
    exclusion_penalty = 0
    
    matched_targets = []
    false_positives = []
    
    for item in items:
        name = item.get("name", "")
        if not name:
            false_positives.append("Unknown Item")
            continue
            
        # Check if this item is one of the targets
        is_target = False
        for target in target_cases:
            # Case-insensitive substring match
            if target.lower() in name.lower() or name.lower() in target.lower():
                if target not in matched_targets:
                    matched_targets.append(target)
                    is_target = True
                    break
        
        if is_target:
            inclusion_score += 6
        else:
            false_positives.append(name)
            exclusion_penalty += 10 # Strict penalty for including wrong items (e.g. Marbury or Obergefell)

    score += inclusion_score
    feedback.append(f"Correctly included {len(matched_targets)}/5 target cases (+{inclusion_score})")
    
    if false_positives:
        score = max(0, score - exclusion_penalty)
        feedback.append(f"Included {len(false_positives)} incorrect items (e.g., '{false_positives[0]}') (-{exclusion_penalty})")
    else:
        # Bonus for perfect exclusion if count was correct? 
        # Actually, let's just say if no false positives and count is < 5, they just missed points on inclusion.
        # If count > 5, false positives logic handles it.
        pass

    # Normalize score
    score = min(100, max(0, score))
    
    # Pass threshold: 80
    # This means they can miss at most 1 case OR have 0 wrong cases.
    # 20 (exist) + 20 (count) + 30 (5*6) = 70... wait.
    # Calculation correction:
    # 20 (creation)
    # 20 (count 5)
    # 30 (inclusion - 5 items * 6 pts = 30)
    # 30 (exclusion - implicit in not losing points?)
    #
    # Let's adjust scoring logic to match Rubric exactly:
    # Rubric:
    # "Warren Court" collection created: 20
    # Correct Item Count: 20
    # Inclusion of Key Cases: 30 (6 pts each)
    # Exclusion of Invalid Items: 30 (implied remainder? No, typically explicit)
    
    # Revised Scoring Implementation to sum to 100 explicitly:
    # Base: 0
    # Created: +20
    # Count == 5: +20
    # Matches: +6 per match (max 30)
    # No False Positives: +30
    
    final_score = 0
    
    # Criterion 1: Created
    if result.get("collection_exists"):
        final_score += 20
    
    # Criterion 2: Count
    if item_count == 5:
        final_score += 20
    
    # Criterion 3: Matches
    final_score += (len(matched_targets) * 6)
    
    # Criterion 4: No False Positives
    if len(false_positives) == 0:
        final_score += 30
    
    passed = final_score >= 80

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback),
        "details": {
            "matched": matched_targets,
            "incorrect": false_positives,
            "total_items": item_count
        }
    }