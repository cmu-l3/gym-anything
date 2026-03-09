#!/usr/bin/env python3
"""
Verifier for remove_from_collection task.

Scoring Breakdown (100 pts total):
1. Collection Integrity (20 pts):
   - Collection "Thesis References" still exists and ID matches (wasn't deleted/recreated): 10 pts
   - Final item count is exactly 8: 10 pts

2. Removal Verification (48 pts - 12 pts each):
   - Einstein paper NOT in collection: 12 pts
   - Watson & Crick paper NOT in collection: 12 pts
   - Goodfellow (GANs) paper NOT in collection: 12 pts
   - Silver (AlphaGo) paper NOT in collection: 12 pts

3. Retention Verification (20 pts - 5 pts each):
   - Einstein paper still in library (not trashed): 5 pts
   - Watson & Crick paper still in library: 5 pts
   - Goodfellow paper still in library: 5 pts
   - Silver paper still in library: 5 pts

4. Collateral Damage Check (12 pts):
   - All 8 kept papers still in collection (1.5 pts each)

Pass Threshold: 60 points
"""

import json
import tempfile
import os

def verify_remove_from_collection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback_parts = []
    
    # 1. Collection Integrity
    if result.get("collection_exists") and result.get("collection_id_match"):
        score += 10
        feedback_parts.append("Collection integrity verified")
    else:
        feedback_parts.append("Collection missing or recreated")

    if result.get("final_collection_count") == 8:
        score += 10
        feedback_parts.append("Correct final count (8)")
    else:
        feedback_parts.append(f"Wrong count: {result.get('final_collection_count')}")

    # 2 & 3. Check Removed Papers (Removal + Retention)
    removed_status = result.get("removed_papers_status", {})
    correctly_removed = 0
    correctly_retained = 0
    
    for title, status in removed_status.items():
        short_title = title[:20] + "..."
        if status.get("found"):
            # Check removal
            if not status.get("in_collection"):
                score += 12
                correctly_removed += 1
            else:
                feedback_parts.append(f"Failed to remove: {short_title}")
            
            # Check retention
            if status.get("in_library") and not status.get("trashed"):
                score += 5
                correctly_retained += 1
            else:
                feedback_parts.append(f"Accidentally trashed: {short_title}")
        else:
            feedback_parts.append(f"Paper missing entirely: {short_title}")

    if correctly_removed == 4:
        feedback_parts.append("All targets removed from collection")
    
    if correctly_retained == 4:
        feedback_parts.append("All targets retained in library")

    # 4. Check Kept Papers
    kept_status = result.get("kept_papers_status", {})
    kept_count = 0
    for title, status in kept_status.items():
        if status.get("in_collection"):
            kept_count += 1
            score += 1.5
    
    # Round score to nearest integer
    score = int(score)
    
    if kept_count == 8:
        feedback_parts.append("Other papers preserved")
    else:
        feedback_parts.append(f"Collateral damage: {8 - kept_count} papers lost")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "removed_count": correctly_removed,
            "retained_count": correctly_retained,
            "kept_preserved": kept_count
        }
    }