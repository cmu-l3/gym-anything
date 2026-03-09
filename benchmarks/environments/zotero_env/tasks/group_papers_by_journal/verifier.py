#!/usr/bin/env python3
"""
Verifier for group_papers_by_journal task.

Scoring Breakdown (100 pts total):
- "Nature Papers" collection exists: 10 pts
- "NeurIPS Papers" collection exists: 10 pts
- Correct Nature papers found: 30 pts (10 each)
- Correct NeurIPS papers found: 40 pts (10 each)
- Deductions: -5 for each incorrect paper in a collection (capped at 0 for that collection's paper points)

Threshold: 80 points
"""

import json
import tempfile
import os

def verify_group_papers_by_journal(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check Collections (20 pts)
    if result.get("nature_collection_exists"):
        score += 10
        feedback_parts.append("'Nature Papers' collection created (+10)")
    else:
        feedback_parts.append("'Nature Papers' collection missing")

    if result.get("neurips_collection_exists"):
        score += 10
        feedback_parts.append("'NeurIPS Papers' collection created (+10)")
    else:
        feedback_parts.append("'NeurIPS Papers' collection missing")

    # Check Nature Papers (30 pts)
    found_nature = result.get("nature_papers_found", [])
    wrong_nature = result.get("nature_papers_wrong", [])
    
    # Expected count is 3
    nature_pts = len(found_nature) * 10
    if nature_pts > 30: nature_pts = 30 # Cap at max
    
    # Deduct for wrong
    deduction = len(wrong_nature) * 5
    final_nature_score = max(0, nature_pts - deduction)
    score += final_nature_score
    
    if len(found_nature) > 0:
        feedback_parts.append(f"Found {len(found_nature)}/3 Nature papers (+{final_nature_score})")
    if len(wrong_nature) > 0:
        feedback_parts.append(f"{len(wrong_nature)} incorrect items in Nature collection")

    # Check NeurIPS Papers (40 pts)
    found_neurips = result.get("neurips_papers_found", [])
    wrong_neurips = result.get("neurips_papers_wrong", [])
    
    # Expected count is 4
    neurips_pts = len(found_neurips) * 10
    if neurips_pts > 40: neurips_pts = 40
    
    # Deduct for wrong
    deduction = len(wrong_neurips) * 5
    final_neurips_score = max(0, neurips_pts - deduction)
    score += final_neurips_score
    
    if len(found_neurips) > 0:
        feedback_parts.append(f"Found {len(found_neurips)}/4 NeurIPS papers (+{final_neurips_score})")
    if len(wrong_neurips) > 0:
        feedback_parts.append(f"{len(wrong_neurips)} incorrect items in NeurIPS collection")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }