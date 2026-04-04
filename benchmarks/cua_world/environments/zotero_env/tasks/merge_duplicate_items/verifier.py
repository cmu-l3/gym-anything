#!/usr/bin/env python3
"""
Verifier for merge_duplicate_items task.
"""

import json
import tempfile
import os

def verify_merge_duplicate_items(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parsing
    analysis = result.get("analysis", {})
    if not analysis.get("db_exists", False):
         return {"passed": False, "score": 0, "feedback": "Database analysis failed"}
         
    final_count = analysis.get("final_count", 0)
    trash_count = analysis.get("trash_count", 0)
    metadata = analysis.get("metadata_checks", {})
    initial_count = int(result.get("initial_count", 0))

    score = 0
    feedback = []
    
    # 1. Merge Count (Target 18 items)
    # 22 initial - 4 merged = 18 target
    if final_count == 18:
        score += 25
        feedback.append("Correct final item count (18)")
    elif final_count < 18:
        feedback.append(f"Too few items ({final_count}) - may have deleted too many")
    elif final_count < 22:
        # Partial credit for some merges
        merges = 22 - final_count
        pts = merges * 5
        score += pts
        feedback.append(f"Partial merges completed ({final_count} remaining)")
    else:
        feedback.append("No items merged (count still 22+)")

    # 2. Trash Count (Items should be in trash, not destroyed)
    # Zotero merge puts duplicates in trash
    if trash_count >= 4:
        score += 15
        feedback.append("Duplicates moved to trash correctly")
    elif trash_count > 0:
        score += 5
        feedback.append("Some items in trash")
    else:
        feedback.append("No items in trash (permanently deleted or not merged?)")
        
    # 3. Metadata Checks (15 pts each = 60 pts total)
    # a. Vaswani (Volume 30)
    vaswani = metadata.get("Attention", {})
    if vaswani.get("status") == "correct" and vaswani.get("count") == 1:
        score += 15
        feedback.append("Vaswani: Volume preserved")
    else:
        feedback.append(f"Vaswani: Metadata incorrect (Val: {vaswani.get('value')}, Count: {vaswani.get('count')})")
        
    # b. LeCun (DOI)
    lecun = metadata.get("Deep Learning", {})
    if lecun.get("status") == "correct" and lecun.get("count") == 1:
        score += 15
        feedback.append("LeCun: DOI preserved")
    else:
        feedback.append(f"LeCun: Metadata incorrect (Val: {lecun.get('value')})")

    # c. Shannon (Pages)
    shannon = metadata.get("Shannon", {})
    if shannon.get("status") == "correct" and shannon.get("count") == 1:
        score += 15
        feedback.append("Shannon: Pages preserved")
    else:
        feedback.append(f"Shannon: Metadata incorrect (Val: {shannon.get('value')})")

    # d. Turing (Year 1950)
    turing = metadata.get("Turing", {})
    if turing.get("status") == "correct" and turing.get("count") == 1:
        score += 15
        feedback.append("Turing: Year preserved")
    else:
        feedback.append(f"Turing: Metadata incorrect (Val: {turing.get('value')})")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }