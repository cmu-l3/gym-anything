#!/usr/bin/env python3
"""
Verifier for trash_irrelevant_items task.

Task: Move 4 specific papers to Trash.
1. "On the Electrodynamics of Moving Bodies"
2. "Molecular Structure of Nucleic Acids: A Structure for Deoxyribose Nucleic Acid"
3. "The Mathematical Theory of Communication" (1949)
4. "An Unsolvable Problem of Elementary Number Theory"

Constraint: Do NOT trash "A Mathematical Theory of Communication" (1948).
"""

import json
import tempfile
import os

def verify_trash_irrelevant_items(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_trash_titles = set(metadata.get('target_trash_titles', []))
    critical_keep_titles = set(metadata.get('critical_keep_titles', []))

    # 2. Load Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Analyze Data
    trashed_items = result.get('trashed_items', [])
    remaining_items = result.get('remaining_items', [])
    trash_count = result.get('trash_count', 0)
    timestamps_valid = result.get('timestamps_valid', False)

    score = 0
    feedback_parts = []
    
    # Normalize titles for robust comparison (strip whitespace)
    trashed_set = set(t.strip() for t in trashed_items)
    remaining_set = set(t.strip() for t in remaining_items)

    # CRITERION 1: Target papers in Trash (15 pts each -> 60 max)
    correctly_trashed = 0
    for target in target_trash_titles:
        if target in trashed_set:
            score += 15
            correctly_trashed += 1
        else:
            feedback_parts.append(f"Missed target: '{target}'")
    
    if correctly_trashed == len(target_trash_titles):
        feedback_parts.append("All target papers trashed")
    elif correctly_trashed > 0:
        feedback_parts.append(f"Trashed {correctly_trashed}/{len(target_trash_titles)} targets")

    # CRITERION 2: No Collateral Damage (20 pts)
    # Check if any non-target items were trashed
    # Specifically check the Critical Keep items
    
    collateral_damage = False
    critical_failure = False
    
    for item in trashed_set:
        if item not in target_trash_titles:
            collateral_damage = True
            # Check for high-penalty items (e.g. the 1948 Shannon paper)
            if item in critical_keep_titles:
                critical_failure = True
                feedback_parts.append(f"CRITICAL ERROR: You trashed '{item}' which must be kept!")

    if critical_failure:
        score -= 20 # Penalty for confusing the Shannon papers
        feedback_parts.append("Penalty for trashing critical item")
    elif not collateral_damage:
        score += 20
        feedback_parts.append("Perfect precision (no extra items trashed)")
    else:
        feedback_parts.append("Wrong items were trashed")

    # CRITERION 3: Exact Count (10 pts)
    if trash_count == 4 and correctly_trashed == 4 and not collateral_damage:
        score += 10
        feedback_parts.append("Trash count exactly 4")
    elif trash_count > 4:
        feedback_parts.append(f"Trash contains too many items ({trash_count})")
    elif trash_count < 4:
        feedback_parts.append(f"Trash contains too few items ({trash_count})")

    # CRITERION 4: Anti-Gaming / Timestamps (10 pts)
    if timestamps_valid and trash_count > 0:
        score += 10
    
    # Cap score at 0 if negative
    score = max(0, score)

    # Pass Threshold
    passed = (score >= 60) and (not critical_failure)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }